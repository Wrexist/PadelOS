import Foundation

/// A round as produced by a scheduler, before match IDs are assigned.
struct PlannedRound: Sendable {
    var number: Int
    var kind: RoundKind
    var matches: [(sideA: MatchSide, sideB: MatchSide)]
    var restingPlayers: [PlayerID]
    var restingTeams: [TeamID]

    func materialize(ids: IdentifierGenerating) -> Round {
        let built = matches.enumerated().map { index, pair in
            Match(id: MatchID(ids.next()), roundNumber: number, court: index + 1, sideA: pair.sideA, sideB: pair.sideB)
        }
        return Round(number: number, kind: kind, matches: built, restingPlayerIDs: restingPlayers, restingTeamIDs: restingTeams)
    }
}

/// Courts actually usable per round. Never exceeds the configured court count.
public enum Capacity {
    public static func matchesPerRound(format: TournamentFormat, courts: Int, players: [Player], teamCount: Int) -> Int {
        if format.usesTeams { return max(0, min(courts, teamCount / 2)) }
        if format.usesGroups {
            let a = players.filter { $0.group == .a }.count
            let b = players.filter { $0.group == .b }.count
            return max(0, min(courts, a / 2, b / 2))
        }
        return max(0, min(courts, players.count / 4))
    }
}

// MARK: - Americano (classic and mixed)

enum AmericanoScheduler {
    /// Generates `count` rounds numbered from `startNumber`, continuing from `existing`.
    /// Runs several complete candidate schedules from independent seeded streams and keeps
    /// the one with the best whole-schedule objective (best-of-K).
    static func generate(
        players: [Player],
        isMixed: Bool,
        courts: Int,
        existing: [Round],
        startNumber: Int,
        count: Int,
        seed: UInt64
    ) -> [PlannedRound] {
        guard count > 0 else { return [] }
        let matchCount = Capacity.matchesPerRound(format: isMixed ? .mixedAmericano : .americano, courts: courts, players: players, teamCount: 0)
        guard matchCount > 0 else { return [] }
        let baseHistory = PlayerHistory.players(from: existing)
        let work = max(1, players.count * count)
        let candidates = max(4, min(24, 2400 / work))

        var best: [PlannedRound] = []
        var bestScore = Int.max
        for candidate in 0..<candidates {
            var history = baseHistory
            var planned: [PlannedRound] = []
            for offset in 0..<count {
                let number = startNumber + offset
                var random = SeededGenerator(seed: seed, streams: 1, UInt64(number), UInt64(candidate))
                let round = planRound(players: players, isMixed: isMixed, matchCount: matchCount, number: number, history: history, random: &random)
                apply(round, to: &history)
                planned.append(round)
            }
            let score = ScheduleObjective.individual(history)
            if score < bestScore {
                bestScore = score
                best = planned
            }
        }
        return best
    }

    static func planRound(players: [Player], isMixed: Bool, matchCount: Int, number: Int, history: PlayerHistory, random: inout SeededGenerator) -> PlannedRound {
        var active: [PlayerID]
        var resting: [PlayerID]
        if isMixed {
            let groupA = players.filter { $0.group == .a }.map(\.id)
            let groupB = players.filter { $0.group == .b }.map(\.id)
            let restA = RestSelector.select(count: groupA.count - 2 * matchCount, from: groupA, history: history, roundNumber: number, random: &random)
            let restB = RestSelector.select(count: groupB.count - 2 * matchCount, from: groupB, history: history, roundNumber: number, random: &random)
            resting = restA + restB
            active = groupA.filter { !restA.contains($0) } + groupB.filter { !restB.contains($0) }
        } else {
            let ids = players.map(\.id)
            resting = RestSelector.select(count: ids.count - 4 * matchCount, from: ids, history: history, roundNumber: number, random: &random)
            active = ids.filter { !resting.contains($0) }
        }
        let optimizer = DoublesOptimizer(players: active, history: history, isMixed: isMixed)
        let (arrangement, _) = optimizer.optimize(matchCount: matchCount, restarts: 8, random: &random)
        var matches: [(MatchSide, MatchSide)] = []
        for j in 0..<matchCount {
            let a = [active[arrangement[4 * j]], active[arrangement[4 * j + 1]]]
            let b = [active[arrangement[4 * j + 2]], active[arrangement[4 * j + 3]]]
            matches.append((MatchSide(playerIDs: a), MatchSide(playerIDs: b)))
        }
        return PlannedRound(number: number, kind: .regular, matches: matches, restingPlayers: resting, restingTeams: [])
    }

    static func apply(_ round: PlannedRound, to history: inout PlayerHistory) {
        for match in round.matches {
            history.recordDoubles(sideA: match.sideA.playerIDs, sideB: match.sideB.playerIDs)
        }
        history.recordRest(round.restingPlayers, round: round.number)
        history.roundsRecorded += 1
    }
}

/// Whole-schedule objective used to compare candidate schedules. Lower is better.
/// Priorities: partner repeats ≫ consecutive rests > uneven opponent exposure.
enum ScheduleObjective {
    static func individual(_ history: PlayerHistory) -> Int {
        1000 * history.partners.repeats
            + 300 * history.consecutiveRestViolations
            + 10 * history.opponents.sumOfSquares
    }

    static func team(_ history: TeamHistory) -> Int {
        1000 * history.opponents.repeats
            + 300 * history.consecutiveRestViolations
            + 10 * history.opponents.sumOfSquares
    }
}

// MARK: - Team Americano

enum TeamScheduler {
    static func generate(
        teams: [Team],
        courts: Int,
        existing: [Round],
        startNumber: Int,
        count: Int,
        seed: UInt64
    ) -> [PlannedRound] {
        guard count > 0 else { return [] }
        let matchCount = min(courts, teams.count / 2)
        guard matchCount > 0 else { return [] }
        // With no history and every team (or all but one) playing each round, the circle
        // method produces a perfect round robin: no repeated pairing until all have met.
        if existing.isEmpty && matchCount == teams.count / 2 {
            return circleMethod(teams: teams, startNumber: startNumber, count: count, seed: seed)
        }
        // Fewer courts than pairs: compare a round-robin queue (keeps the perfect pairing
        // order of the circle method) with history-aware local search, keep the better.
        let searched = optimized(teams: teams, matchCount: matchCount, existing: existing, startNumber: startNumber, count: count, seed: seed)
        let queued = roundRobinQueue(teams: teams, matchCount: matchCount, existing: existing, startNumber: startNumber, count: count, seed: seed)
        return evaluate(queued, existing: existing, teams: teams) < evaluate(searched, existing: existing, teams: teams) ? queued : searched
    }

    static func evaluate(_ planned: [PlannedRound], existing: [Round], teams: [Team]) -> Int {
        var history = TeamHistory.teams(from: existing)
        for round in planned {
            for match in round.matches {
                if let a = match.sideA.teamID, let b = match.sideB.teamID { history.recordSingle(a, b) }
            }
            history.recordRest(round.restingTeams, round: round.number)
        }
        let played = teams.map { history.playedCount($0.id) }
        let spread = (played.max() ?? 0) - (played.min() ?? 0)
        return ScheduleObjective.team(history) + 5000 * max(0, spread - 1)
    }

    /// Walks the circle-method pairing order. Each round takes the earliest pairings whose
    /// teams are still free, preferring teams that have played least, so the round robin
    /// completes before any pairing repeats whenever capacity allows.
    static func roundRobinQueue(teams: [Team], matchCount: Int, existing: [Round], startNumber: Int, count: Int, seed: UInt64) -> [PlannedRound] {
        var history = TeamHistory.teams(from: existing)
        let cycle = circleMethod(teams: teams, startNumber: 1, count: max(1, teams.count - (teams.count % 2 == 0 ? 1 : 0)), seed: seed)
            .flatMap { $0.matches.map { ($0.sideA.teamID!, $0.sideB.teamID!) } }
        var queue: [(TeamID, TeamID)] = []
        var planned: [PlannedRound] = []
        for offset in 0..<count {
            let number = startNumber + offset
            if queue.count < matchCount * 2 { queue += cycle }
            // Unplayed pairings first, then by fewest matches played, then queue order.
            let ranked = queue.enumerated().sorted { x, y in
                let rx = history.opponents[x.element.0, x.element.1], ry = history.opponents[y.element.0, y.element.1]
                if rx != ry { return rx < ry }
                let px = history.playedCount(x.element.0) + history.playedCount(x.element.1)
                let py = history.playedCount(y.element.0) + history.playedCount(y.element.1)
                if px != py { return px < py }
                return x.offset < y.offset
            }
            var busy = Set<TeamID>()
            var chosen: [Int] = []
            for (index, pair) in ranked where chosen.count < matchCount {
                if busy.contains(pair.0) || busy.contains(pair.1) { continue }
                busy.insert(pair.0)
                busy.insert(pair.1)
                chosen.append(index)
            }
            var matches: [(MatchSide, MatchSide)] = []
            for index in chosen {
                let (x, y) = queue[index]
                let tx = teams.first { $0.id == x }!, ty = teams.first { $0.id == y }!
                matches.append((side(tx), side(ty)))
                history.recordSingle(x, y)
            }
            for index in chosen.sorted(by: >) { queue.remove(at: index) }
            let resting = teams.map(\.id).filter { !busy.contains($0) }
            history.recordRest(resting, round: number)
            let restingPlayers = resting.flatMap { id in teams.first { $0.id == id }?.playerIDs ?? [] }
            planned.append(PlannedRound(number: number, kind: .regular, matches: matches, restingPlayers: restingPlayers, restingTeams: resting))
        }
        return planned
    }

    static func side(_ team: Team) -> MatchSide {
        MatchSide(playerIDs: team.playerIDs, teamID: team.id)
    }

    static func circleMethod(teams: [Team], startNumber: Int, count: Int, seed: UInt64) -> [PlannedRound] {
        var random = SeededGenerator(seed: seed, streams: 2)
        var order: [Team?] = random.shuffled(teams).map { Optional($0) }
        if order.count % 2 == 1 { order.append(nil) } // bye
        let n = order.count
        var rounds: [PlannedRound] = []
        var rotation = order
        for offset in 0..<count {
            if offset > 0 && offset % (n - 1) == 0 {
                rotation = order // a new cycle repeats the same order
            }
            var matches: [(MatchSide, MatchSide)] = []
            var resting: [TeamID] = []
            for i in 0..<(n / 2) {
                let x = rotation[i], y = rotation[n - 1 - i]
                switch (x, y) {
                case let (x?, y?):
                    // Alternate sides so no team is always listed first.
                    matches.append(offset % 2 == 0 ? (side(x), side(y)) : (side(y), side(x)))
                case let (x?, nil): resting.append(x.id)
                case let (nil, y?): resting.append(y.id)
                case (nil, nil): break
                }
            }
            rounds.append(PlannedRound(number: startNumber + offset, kind: .regular, matches: matches, restingPlayers: resting.flatMap { id in teams.first { $0.id == id }?.playerIDs ?? [] }, restingTeams: resting))
            // Rotate all but the first element clockwise.
            let last = rotation.removeLast()
            rotation.insert(last, at: 1)
        }
        return rounds
    }

    static func optimized(teams: [Team], matchCount: Int, existing: [Round], startNumber: Int, count: Int, seed: UInt64) -> [PlannedRound] {
        let baseHistory = TeamHistory.teams(from: existing)
        let candidates = max(4, min(24, 2400 / max(1, teams.count * count)))
        var best: [PlannedRound] = []
        var bestScore = Int.max
        for candidate in 0..<candidates {
            var history = baseHistory
            var planned: [PlannedRound] = []
            for offset in 0..<count {
                let number = startNumber + offset
                var random = SeededGenerator(seed: seed, streams: 3, UInt64(number), UInt64(candidate))
                let ids = teams.map(\.id)
                let resting = RestSelector.select(count: ids.count - 2 * matchCount, from: ids, history: history, roundNumber: number, random: &random)
                let active = ids.filter { !resting.contains($0) }
                let pairs = pairTeams(active, history: history, random: &random)
                var matches: [(MatchSide, MatchSide)] = []
                for (x, y) in pairs {
                    let tx = teams.first { $0.id == x }!, ty = teams.first { $0.id == y }!
                    matches.append((side(tx), side(ty)))
                    history.recordSingle(x, y)
                }
                history.recordRest(resting, round: number)
                history.roundsRecorded += 1
                let restingPlayers = resting.flatMap { id in teams.first { $0.id == id }?.playerIDs ?? [] }
                planned.append(PlannedRound(number: number, kind: .regular, matches: matches, restingPlayers: restingPlayers, restingTeams: resting))
            }
            let score = ScheduleObjective.team(history)
            if score < bestScore {
                bestScore = score
                best = planned
            }
        }
        return best
    }

    /// Pairs active teams minimising Σ c² over previous meetings, by pair-swap descent.
    static func pairTeams(_ active: [TeamID], history: TeamHistory, random: inout SeededGenerator) -> [(TeamID, TeamID)] {
        func cost(_ x: TeamID, _ y: TeamID) -> Int {
            let c = history.opponents[x, y]
            return c * c
        }
        var bestArrangement: [TeamID] = []
        var bestCost = Int.max
        for _ in 0..<8 {
            var arrangement = random.shuffled(active)
            var improved = true
            while improved {
                improved = false
                for i in 0..<arrangement.count {
                    for j in (i + 1)..<arrangement.count where i / 2 != j / 2 {
                        let pi = i / 2, pj = j / 2
                        let before = cost(arrangement[2 * pi], arrangement[2 * pi + 1]) + cost(arrangement[2 * pj], arrangement[2 * pj + 1])
                        arrangement.swapAt(i, j)
                        let after = cost(arrangement[2 * pi], arrangement[2 * pi + 1]) + cost(arrangement[2 * pj], arrangement[2 * pj + 1])
                        if after < before {
                            improved = true
                        } else {
                            arrangement.swapAt(i, j)
                        }
                    }
                }
            }
            let total = stride(from: 0, to: arrangement.count, by: 2).reduce(0) { $0 + cost(arrangement[$1], arrangement[$1 + 1]) }
            if total < bestCost {
                bestCost = total
                bestArrangement = arrangement
                if total == 0 { break }
            }
        }
        return stride(from: 0, to: bestArrangement.count, by: 2).map { (bestArrangement[$0], bestArrangement[$0 + 1]) }
    }
}

// MARK: - Mexicano

enum MexicanoScheduler {
    static let partnerWeight = 100
    static let opponentWeight = 5
    static let displacementWeight = 25
    static let secondaryPatternPenalty = 15
    static let tertiaryPatternPenalty = 40

    /// Plans one Mexicano round.
    /// - Parameters:
    ///   - ranking: active players ordered best first, from standings of completed rounds
    ///     only. For round 1 this is the seeded draw or list order.
    static func planRound(
        ranking: [PlayerID],
        courts: Int,
        number: Int,
        history: PlayerHistory,
        pattern: MexicanoPairingPattern,
        seed: UInt64
    ) -> PlannedRound {
        let matchCount = min(courts, ranking.count / 4)
        var random = SeededGenerator(seed: seed, streams: 4, UInt64(number))
        let resting = RestSelector.select(count: ranking.count - 4 * matchCount, from: ranking, history: history, roundNumber: number, random: &random)
        let active = ranking.filter { !resting.contains($0) }
        let groups = arrange(active: active, history: history, pattern: pattern)
        let matches = groups.map { (MatchSide(playerIDs: $0.teamA), MatchSide(playerIDs: $0.teamB)) }
        return PlannedRound(number: number, kind: .regular, matches: matches, restingPlayers: resting, restingTeams: [])
    }

    struct GroupPlan {
        var teamA: [PlayerID]
        var teamB: [PlayerID]
        var cost: Int
    }

    /// Pairings for four players listed by rank, best first, in preference order.
    static func patterns(_ preferred: MexicanoPairingPattern) -> [((Int, Int), (Int, Int), Int)] {
        let oneFour = ((0, 3), (1, 2))
        let oneThree = ((0, 2), (1, 3))
        let oneTwo = ((0, 1), (2, 3))
        switch preferred {
        case .oneFourVsTwoThree:
            return [(oneFour.0, oneFour.1, 0), (oneThree.0, oneThree.1, secondaryPatternPenalty), (oneTwo.0, oneTwo.1, tertiaryPatternPenalty)]
        case .oneThreeVsTwoFour:
            return [(oneThree.0, oneThree.1, 0), (oneFour.0, oneFour.1, secondaryPatternPenalty), (oneTwo.0, oneTwo.1, tertiaryPatternPenalty)]
        }
    }

    static func bestPlan(for group: [PlayerID], history: PlayerHistory, pattern: MexicanoPairingPattern) -> GroupPlan {
        var best: GroupPlan?
        for (a, b, penalty) in patterns(pattern) {
            let teamA = [group[a.0], group[a.1]]
            let teamB = [group[b.0], group[b.1]]
            let pa = history.partners[teamA[0], teamA[1]], pb = history.partners[teamB[0], teamB[1]]
            var cost = penalty + partnerWeight * (pa * pa + pb * pb)
            for x in teamA { for y in teamB { let c = history.opponents[x, y]; cost += opponentWeight * c * c } }
            if best == nil || cost < best!.cost {
                best = GroupPlan(teamA: teamA, teamB: teamB, cost: cost)
            }
        }
        return best!
    }

    /// Groups players into blocks of four by rank, then improves by swapping players
    /// between adjacent blocks when that avoids repeats enough to justify moving a
    /// player away from their ranked block. Deterministic for a given input.
    static func arrange(active: [PlayerID], history: PlayerHistory, pattern: MexicanoPairingPattern) -> [GroupPlan] {
        let groupCount = active.count / 4
        guard groupCount > 0 else { return [] }
        let naturalGroup = Dictionary(uniqueKeysWithValues: active.enumerated().map { ($1, $0 / 4) })
        let rankIndex = Dictionary(uniqueKeysWithValues: active.enumerated().map { ($1, $0) })
        var blocks = (0..<groupCount).map { Array(active[(4 * $0)..<(4 * $0 + 4)]) }

        func blockCost(_ block: [PlayerID], _ g: Int) -> Int {
            let sorted = block.sorted { rankIndex[$0]! < rankIndex[$1]! }
            let displaced = block.reduce(0) { $0 + abs(naturalGroup[$1]! - g) }
            return bestPlan(for: sorted, history: history, pattern: pattern).cost + displacementWeight * displaced
        }

        var costs = blocks.enumerated().map { blockCost($1, $0) }
        var improved = true
        while improved {
            improved = false
            var bestDelta = 0
            var bestMove: (g: Int, i: Int, j: Int)?
            for g in 0..<(groupCount - 1) {
                for i in 0..<4 {
                    for j in 0..<4 {
                        var upper = blocks[g], lower = blocks[g + 1]
                        swap(&upper[i], &lower[j])
                        let delta = blockCost(upper, g) + blockCost(lower, g + 1) - costs[g] - costs[g + 1]
                        if delta < bestDelta {
                            bestDelta = delta
                            bestMove = (g, i, j)
                        }
                    }
                }
            }
            if let move = bestMove {
                let moved = blocks[move.g][move.i]
                blocks[move.g][move.i] = blocks[move.g + 1][move.j]
                blocks[move.g + 1][move.j] = moved
                costs[move.g] = blockCost(blocks[move.g], move.g)
                costs[move.g + 1] = blockCost(blocks[move.g + 1], move.g + 1)
                improved = true
            }
        }
        return blocks.map { block in
            let sorted = block.sorted { rankIndex[$0]! < rankIndex[$1]! }
            return bestPlan(for: sorted, history: history, pattern: pattern)
        }
    }
}

// MARK: - Standings-based final round

enum FinalRoundScheduler {
    /// Top-ranked players play; court 1 hosts the top four (1 & 4 vs 2 & 3 by default).
    /// Lowest-ranked players rest when capacity is short. No repeat avoidance: the point
    /// of a final round is that the best players meet.
    static func individual(ranking: [PlayerID], players: [Player], isMixed: Bool, courts: Int, number: Int, pattern: MexicanoPairingPattern) -> PlannedRound {
        if isMixed {
            let groupA = ranking.filter { id in players.first { $0.id == id }?.group == .a }
            let groupB = ranking.filter { id in players.first { $0.id == id }?.group == .b }
            let matchCount = min(courts, groupA.count / 2, groupB.count / 2)
            var matches: [(MatchSide, MatchSide)] = []
            for g in 0..<matchCount {
                // Strongest of each group partners the second strongest of the other group.
                let teamA = [groupA[2 * g], groupB[2 * g + 1]]
                let teamB = [groupA[2 * g + 1], groupB[2 * g]]
                matches.append((MatchSide(playerIDs: teamA), MatchSide(playerIDs: teamB)))
            }
            let resting = Array(groupA.dropFirst(2 * matchCount)) + Array(groupB.dropFirst(2 * matchCount))
            return PlannedRound(number: number, kind: .final, matches: matches, restingPlayers: resting, restingTeams: [])
        }
        let matchCount = min(courts, ranking.count / 4)
        var matches: [(MatchSide, MatchSide)] = []
        let preferred = MexicanoScheduler.patterns(pattern)[0]
        for g in 0..<matchCount {
            let group = Array(ranking[(4 * g)..<(4 * g + 4)])
            let teamA = [group[preferred.0.0], group[preferred.0.1]]
            let teamB = [group[preferred.1.0], group[preferred.1.1]]
            matches.append((MatchSide(playerIDs: teamA), MatchSide(playerIDs: teamB)))
        }
        return PlannedRound(number: number, kind: .final, matches: matches, restingPlayers: Array(ranking.dropFirst(4 * matchCount)), restingTeams: [])
    }

    /// 1st vs 2nd on court 1, 3rd vs 4th on court 2, …
    static func team(ranking: [TeamID], teams: [Team], courts: Int, number: Int) -> PlannedRound {
        let matchCount = min(courts, ranking.count / 2)
        var matches: [(MatchSide, MatchSide)] = []
        for g in 0..<matchCount {
            let x = teams.first { $0.id == ranking[2 * g] }!, y = teams.first { $0.id == ranking[2 * g + 1] }!
            matches.append((TeamScheduler.side(x), TeamScheduler.side(y)))
        }
        let restingTeams = Array(ranking.dropFirst(2 * matchCount))
        let restingPlayers = restingTeams.flatMap { id in teams.first { $0.id == id }?.playerIDs ?? [] }
        return PlannedRound(number: number, kind: .final, matches: matches, restingPlayers: restingPlayers, restingTeams: restingTeams)
    }
}
