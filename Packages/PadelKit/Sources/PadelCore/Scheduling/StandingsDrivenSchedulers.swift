import Foundation

/// Costs shared by the standings-driven formats (lower is better). They mirror the
/// Mexicano weights so all "pair by standings" formats behave consistently:
/// a repeat partnership (+100·c²) is worth moving a player one block (+25) or using the
/// less balanced pairing (+15); repeat opponents cost +5·c².
enum StandingsCosts {
    static let partner = 100
    static let opponent = 5
    static let displacement = 25
    static let unbalancedPairing = 15

    static func doubles(teamA: [PlayerID], teamB: [PlayerID], history: PlayerHistory) -> Int {
        let pa = history.partners[teamA[0], teamA[1]], pb = history.partners[teamB[0], teamB[1]]
        var cost = partner * (pa * pa + pb * pb)
        for x in teamA { for y in teamB { let c = history.opponents[x, y]; cost += opponent * c * c } }
        return cost
    }
}

// MARK: - Mixicano

/// Mexicano where every team has one player from each group. Each group is ranked
/// separately (from the overall standings); court g takes the g-th pair of each group.
/// Preferred pairing inside a court: strongest A with weaker B against weaker A with
/// strongest B, which balances the two teams.
enum MixicanoScheduler {
    struct Block {
        var a: [PlayerID]
        var b: [PlayerID]
    }

    static func planRound(rankingA: [PlayerID], rankingB: [PlayerID], courts: Int, number: Int, history: PlayerHistory, seed: UInt64) -> PlannedRound {
        let matchCount = min(courts, rankingA.count / 2, rankingB.count / 2)
        var random = SeededGenerator(seed: seed, streams: 6, UInt64(number))
        let restA = RestSelector.select(count: rankingA.count - 2 * matchCount, from: rankingA, history: history, roundNumber: number, random: &random)
        let restB = RestSelector.select(count: rankingB.count - 2 * matchCount, from: rankingB, history: history, roundNumber: number, random: &random)
        let activeA = rankingA.filter { !restA.contains($0) }
        let activeB = rankingB.filter { !restB.contains($0) }
        let blocks = arrange(activeA: activeA, activeB: activeB, matchCount: matchCount, history: history)
        let matches = blocks.map { plan in (MatchSide(playerIDs: plan.teamA), MatchSide(playerIDs: plan.teamB)) }
        return PlannedRound(number: number, kind: .regular, matches: matches, restingPlayers: restA + restB, restingTeams: [])
    }

    struct Plan {
        var teamA: [PlayerID]
        var teamB: [PlayerID]
        var cost: Int
    }

    static func bestPlan(_ block: Block, rank: [PlayerID: Int], history: PlayerHistory) -> Plan {
        let a = block.a.sorted { rank[$0]! < rank[$1]! }
        let b = block.b.sorted { rank[$0]! < rank[$1]! }
        let options: [([PlayerID], [PlayerID], Int)] = [
            ([a[0], b[1]], [a[1], b[0]], 0),
            ([a[0], b[0]], [a[1], b[1]], StandingsCosts.unbalancedPairing),
        ]
        var best: Plan?
        for (teamA, teamB, penalty) in options {
            let cost = penalty + StandingsCosts.doubles(teamA: teamA, teamB: teamB, history: history)
            if best == nil || cost < best!.cost { best = Plan(teamA: teamA, teamB: teamB, cost: cost) }
        }
        return best!
    }

    static func arrange(activeA: [PlayerID], activeB: [PlayerID], matchCount: Int, history: PlayerHistory) -> [Plan] {
        guard matchCount > 0 else { return [] }
        var rank: [PlayerID: Int] = [:]
        var natural: [PlayerID: Int] = [:]
        for (i, id) in activeA.enumerated() { rank[id] = i; natural[id] = i / 2 }
        for (i, id) in activeB.enumerated() { rank[id] = i; natural[id] = i / 2 }
        var blocks = (0..<matchCount).map { g in Block(a: Array(activeA[(2 * g)..<(2 * g + 2)]), b: Array(activeB[(2 * g)..<(2 * g + 2)])) }

        func cost(_ block: Block, _ g: Int) -> Int {
            // 25 per court moved, plus a small rank-based amount so ties keep the stronger
            // players in place.
            let displaced = (block.a + block.b).reduce(0) { total, id in
                let distance = abs(natural[id]! - g)
                return total + (distance == 0 ? 0 : StandingsCosts.displacement * distance + (matchCount - natural[id]!))
            }
            return bestPlan(block, rank: rank, history: history).cost + displaced
        }

        var costs = blocks.enumerated().map { cost($1, $0) }
        var improved = true
        while improved {
            improved = false
            var bestDelta = 0
            var bestMove: (g: Int, groupA: Bool, i: Int, j: Int)?
            for g in 0..<(matchCount - 1) {
                for groupA in [true, false] {
                    for i in 0..<2 {
                        for j in 0..<2 {
                            var upper = blocks[g], lower = blocks[g + 1]
                            if groupA { swap(&upper.a[i], &lower.a[j]) } else { swap(&upper.b[i], &lower.b[j]) }
                            let delta = cost(upper, g) + cost(lower, g + 1) - costs[g] - costs[g + 1]
                            if delta < bestDelta {
                                bestDelta = delta
                                bestMove = (g, groupA, i, j)
                            }
                        }
                    }
                }
            }
            if let move = bestMove {
                var upper = blocks[move.g], lower = blocks[move.g + 1]
                if move.groupA { swap(&upper.a[move.i], &lower.a[move.j]) } else { swap(&upper.b[move.i], &lower.b[move.j]) }
                blocks[move.g] = upper
                blocks[move.g + 1] = lower
                costs[move.g] = cost(upper, move.g)
                costs[move.g + 1] = cost(lower, move.g + 1)
                improved = true
            }
        }
        return blocks.map { bestPlan($0, rank: rank, history: history) }
    }
}

// MARK: - Team Mexicano

/// Fixed teams paired by the standings: 1st v 2nd, 3rd v 4th, … A local search may swap
/// teams between neighbouring courts (+25 each) to avoid a repeat meeting (+100·c²).
enum TeamMexicanoScheduler {
    static func planRound(ranking: [TeamID], teams: [Team], courts: Int, number: Int, history: TeamHistory, seed: UInt64) -> PlannedRound {
        let matchCount = min(courts, ranking.count / 2)
        var random = SeededGenerator(seed: seed, streams: 7, UInt64(number))
        let resting = RestSelector.select(count: ranking.count - 2 * matchCount, from: ranking, history: history, roundNumber: number, random: &random)
        let active = ranking.filter { !resting.contains($0) }
        let natural = Dictionary(uniqueKeysWithValues: active.enumerated().map { ($1, $0 / 2) })
        var order = active

        // Moving a team costs 25 per court, plus a small amount that grows with its rank,
        // so among equally good fixes the higher-ranked team keeps its court.
        func displacementCost(_ team: TeamID, _ g: Int) -> Int {
            let distance = abs(natural[team]! - g)
            return distance == 0 ? 0 : StandingsCosts.displacement * distance + (matchCount - natural[team]!)
        }

        func pairCost(_ g: Int) -> Int {
            let x = order[2 * g], y = order[2 * g + 1]
            let c = history.opponents[x, y]
            return StandingsCosts.partner * c * c + displacementCost(x, g) + displacementCost(y, g)
        }

        var improved = matchCount > 1
        while improved {
            improved = false
            var bestDelta = 0
            var bestSwap: (Int, Int)?
            for g in 0..<(matchCount - 1) {
                let before = pairCost(g) + pairCost(g + 1)
                for i in [2 * g, 2 * g + 1] {
                    for j in [2 * g + 2, 2 * g + 3] {
                        order.swapAt(i, j)
                        let delta = pairCost(g) + pairCost(g + 1) - before
                        order.swapAt(i, j)
                        if delta < bestDelta {
                            bestDelta = delta
                            bestSwap = (i, j)
                        }
                    }
                }
            }
            if let (i, j) = bestSwap {
                order.swapAt(i, j)
                improved = true
            }
        }

        var matches: [(MatchSide, MatchSide)] = []
        for g in 0..<matchCount {
            let x = teams.first { $0.id == order[2 * g] }!, y = teams.first { $0.id == order[2 * g + 1] }!
            matches.append((TeamScheduler.side(x), TeamScheduler.side(y)))
        }
        let restingPlayers = resting.flatMap { id in teams.first { $0.id == id }?.playerIDs ?? [] }
        return PlannedRound(number: number, kind: .regular, matches: matches, restingPlayers: restingPlayers, restingTeams: resting)
    }
}

// MARK: - King of the Court

/// Court ladder: after each round the winners of court k move up to court k−1 and the
/// losers move down to court k+1 (court 1 winners stay, bottom-court losers stay). A draw
/// keeps both teams on their court. Partners are split on every court: the two players
/// who moved there as winners face each other, each partnered with an arriving loser.
/// Players returning from a rest join the bottom court. Rests follow the fairness rule.
enum KingOfTheCourtScheduler {
    static func planRound(ranking: [PlayerID], previous: Round?, courts: Int, number: Int, history: PlayerHistory, seed: UInt64) -> PlannedRound {
        let matchCount = min(courts, ranking.count / 4)
        var random = SeededGenerator(seed: seed, streams: 8, UInt64(number))
        let resting = RestSelector.select(count: ranking.count - 4 * matchCount, from: ranking, history: history, roundNumber: number, random: &random)
        let rankIndex = Dictionary(uniqueKeysWithValues: ranking.enumerated().map { ($1, $0) })

        // Target court and whether the player arrives as a winner.
        var target: [PlayerID: Int] = [:]
        var arrivedAsWinner: [PlayerID: Bool] = [:]
        var previousCourt: [PlayerID: Int] = [:]
        if let previous {
            for match in previous.matches {
                let winner = ScoringEngine.winner(of: match)
                for side in TeamSide.allCases {
                    let move: Int
                    if !match.isCompleted || winner == nil { move = 0 } else { move = winner == side ? -1 : 1 }
                    for player in match.side(side).playerIDs {
                        target[player] = match.court + move
                        arrivedAsWinner[player] = move < 0 || (move == 0 && winner == nil)
                        previousCourt[player] = match.court
                    }
                }
            }
        }
        let active = ranking.filter { !resting.contains($0) }
        let ordered: [PlayerID]
        if previous == nil {
            ordered = active
        } else {
            ordered = active.sorted { x, y in
                let tx = min(max(target[x] ?? matchCount, 1), matchCount)
                let ty = min(max(target[y] ?? matchCount, 1), matchCount)
                if tx != ty { return tx < ty }
                let wx = arrivedAsWinner[x] ?? false, wy = arrivedAsWinner[y] ?? false
                if wx != wy { return wx }
                let cx = previousCourt[x] ?? Int.max, cy = previousCourt[y] ?? Int.max
                if cx != cy { return cx < cy }
                return rankIndex[x]! < rankIndex[y]!
            }
        }

        var matches: [(MatchSide, MatchSide)] = []
        for g in 0..<matchCount {
            // Order inside the court: arriving winners first, so the preferred 1&4 v 2&3
            // pattern splits previous partners. Repeat partners are still avoided.
            let block = Array(ordered[(4 * g)..<(4 * g + 4)])
            let plan = MexicanoScheduler.bestPlan(for: block, history: history, pattern: .oneFourVsTwoThree)
            matches.append((MatchSide(playerIDs: plan.teamA), MatchSide(playerIDs: plan.teamB)))
        }
        return PlannedRound(number: number, kind: .regular, matches: matches, restingPlayers: resting, restingTeams: [])
    }
}
