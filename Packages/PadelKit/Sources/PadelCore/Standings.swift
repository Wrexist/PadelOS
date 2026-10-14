import Foundation

public enum StandingSubject: Hashable, Sendable {
    case player(PlayerID)
    case team(TeamID)
}

public enum TieBreaker: String, Sendable, CaseIterable {
    case totalPoints
    case wins
    case headToHead
    case pointDifference

    public var displayName: String {
        switch self {
        case .totalPoints: "Total points"
        case .wins: "Matches won"
        case .headToHead: "Head-to-head points (two tied teams)"
        case .pointDifference: "Point difference"
        }
    }
}

public enum RoundOutcome: String, Sendable, Hashable {
    case won, drew, lost, rested, notPlayed
}

public struct RoundResult: Sendable, Hashable, Identifiable {
    public var roundNumber: Int
    public var outcome: RoundOutcome
    public var pointsFor: Int
    public var pointsAgainst: Int
    /// Points credited to the standings for this round (includes rest compensation).
    public var creditedPoints: Int

    public var id: Int { roundNumber }
}

public struct StandingEntry: Sendable, Hashable, Identifiable {
    public var subject: StandingSubject
    public var name: String
    public var rank: Int
    /// True when at least one other entry shares this rank.
    public var isTied: Bool
    public var isWithdrawn: Bool
    /// Ranking total: points scored in completed matches plus any rest compensation.
    public var points: Int
    public var pointsFor: Int
    public var pointsAgainst: Int
    public var wins: Int
    public var draws: Int
    public var losses: Int
    public var played: Int
    public var rested: Int
    public var restPoints: Int
    public var roundResults: [RoundResult]

    public var id: StandingSubject { subject }
    public var pointDifference: Int { pointsFor - pointsAgainst }
}

public struct Standings: Sendable, Hashable {
    public var entries: [StandingEntry]
    public var tieBreakers: [TieBreaker]
    public var isTeamStandings: Bool
    /// Number of completed matches that contributed.
    public var completedMatches: Int

    public func entry(for subject: StandingSubject) -> StandingEntry? {
        entries.first { $0.subject == subject }
    }

    /// Ranking of players, best first (individual formats only).
    public var playerRanking: [PlayerID] {
        entries.compactMap { if case .player(let id) = $0.subject { id } else { nil } }
    }

    public var teamRanking: [TeamID] {
        entries.compactMap { if case .team(let id) = $0.subject { id } else { nil } }
    }
}

/// Derives standings from saved match results. Nothing here is stored: standings can
/// always be rebuilt from the tournament, which is what keeps them consistent.
///
/// Ranking rules (in order):
/// - Individual formats: total points → matches won → point difference → shared rank.
/// - Team Americano: total points → matches won → head-to-head points when exactly two
///   teams are tied → point difference → shared rank.
/// Only completed matches count. Rest compensation, when enabled, is credited for each
/// rest in a completed round.
public enum StandingsCalculator {
    public static func tieBreakers(for format: TournamentFormat) -> [TieBreaker] {
        format.isIndividual ? [.totalPoints, .wins, .pointDifference] : [.totalPoints, .wins, .headToHead, .pointDifference]
    }

    /// - Parameter throughRound: only rounds with `number <= throughRound` are counted.
    public static func compute(_ tournament: Tournament, throughRound: Int? = nil) -> Standings {
        let format = tournament.configuration.format
        let rounds = tournament.rounds.filter { throughRound == nil || $0.number <= throughRound! }
        let restPoints = tournament.configuration.restPoints

        var accumulators: [StandingSubject: StandingEntry] = [:]
        var order: [StandingSubject] = []
        if format.isIndividual {
            for player in tournament.players {
                let subject = StandingSubject.player(player.id)
                order.append(subject)
                accumulators[subject] = blankEntry(subject, name: player.name, withdrawn: tournament.withdrawnPlayerIDs.contains(player.id))
            }
        } else {
            for team in tournament.teams {
                let subject = StandingSubject.team(team.id)
                order.append(subject)
                accumulators[subject] = blankEntry(subject, name: team.name, withdrawn: tournament.withdrawnTeamIDs.contains(team.id))
            }
        }

        var completedMatches = 0
        // Head-to-head points: [team: [opponent: (for, against)]]
        var headToHead: [TeamID: [TeamID: (Int, Int)]] = [:]

        for round in rounds {
            var appearedThisRound = Set<StandingSubject>()
            for match in round.matches {
                let subjectsA = subjects(match.sideA, format: format)
                let subjectsB = subjects(match.sideB, format: format)
                for subject in subjectsA + subjectsB { appearedThisRound.insert(subject) }
                guard match.isCompleted else {
                    for subject in subjectsA + subjectsB {
                        accumulators[subject]?.roundResults.append(RoundResult(roundNumber: round.number, outcome: .notPlayed, pointsFor: 0, pointsAgainst: 0, creditedPoints: 0))
                    }
                    continue
                }
                completedMatches += 1
                let matchWinner = ScoringEngine.winner(of: match)
                for side in TeamSide.allCases {
                    let mine = match.score[side], theirs = match.score[side.opposite]
                    let outcome: RoundOutcome = matchWinner == side ? .won : (matchWinner == side.opposite ? .lost : .drew)
                    for subject in (side == .a ? subjectsA : subjectsB) {
                        guard var entry = accumulators[subject] else { continue }
                        entry.points += mine
                        entry.pointsFor += mine
                        entry.pointsAgainst += theirs
                        entry.played += 1
                        switch outcome {
                        case .won: entry.wins += 1
                        case .lost: entry.losses += 1
                        default: entry.draws += 1
                        }
                        entry.roundResults.append(RoundResult(roundNumber: round.number, outcome: outcome, pointsFor: mine, pointsAgainst: theirs, creditedPoints: mine))
                        accumulators[subject] = entry
                    }
                }
                if let a = match.sideA.teamID, let b = match.sideB.teamID {
                    let previousA = headToHead[a]?[b] ?? (0, 0)
                    headToHead[a, default: [:]][b] = (previousA.0 + match.score.a, previousA.1 + match.score.b)
                    let previousB = headToHead[b]?[a] ?? (0, 0)
                    headToHead[b, default: [:]][a] = (previousB.0 + match.score.b, previousB.1 + match.score.a)
                }
            }
            // Rest credit only once the round is over, so standings never include the future.
            let restingSubjects: [StandingSubject] = format.isIndividual
                ? round.restingPlayerIDs.map { .player($0) }
                : round.restingTeamIDs.map { .team($0) }
            for subject in restingSubjects where !appearedThisRound.contains(subject) {
                guard var entry = accumulators[subject] else { continue }
                let credited = round.isCompleted ? restPoints : 0
                entry.rested += round.isCompleted ? 1 : 0
                entry.restPoints += credited
                entry.points += credited
                entry.roundResults.append(RoundResult(roundNumber: round.number, outcome: .rested, pointsFor: 0, pointsAgainst: 0, creditedPoints: credited))
                accumulators[subject] = entry
            }
        }

        let entries = rank(order.compactMap { accumulators[$0] }, format: format, headToHead: headToHead)
        return Standings(entries: entries, tieBreakers: tieBreakers(for: format), isTeamStandings: !format.isIndividual, completedMatches: completedMatches)
    }

    private static func blankEntry(_ subject: StandingSubject, name: String, withdrawn: Bool) -> StandingEntry {
        StandingEntry(subject: subject, name: name, rank: 0, isTied: false, isWithdrawn: withdrawn, points: 0, pointsFor: 0, pointsAgainst: 0, wins: 0, draws: 0, losses: 0, played: 0, rested: 0, restPoints: 0, roundResults: [])
    }

    private static func subjects(_ side: MatchSide, format: TournamentFormat) -> [StandingSubject] {
        if format.isIndividual { return side.playerIDs.map { .player($0) } }
        return side.teamID.map { [.team($0)] } ?? []
    }

    private static func rank(_ entries: [StandingEntry], format: TournamentFormat, headToHead: [TeamID: [TeamID: (Int, Int)]]) -> [StandingEntry] {
        // Primary keys shared by all formats; name only orders display within a true tie.
        let primary = entries.sorted { x, y in
            if x.points != y.points { return x.points > y.points }
            if x.wins != y.wins { return x.wins > y.wins }
            return x.name.localizedCaseInsensitiveCompare(y.name) == .orderedAscending
        }

        // Split into blocks equal on (points, wins), then resolve each block.
        var resolved: [[StandingEntry]] = [] // groups of entries sharing a rank
        var index = 0
        while index < primary.count {
            var end = index + 1
            while end < primary.count && primary[end].points == primary[index].points && primary[end].wins == primary[index].wins { end += 1 }
            let block = Array(primary[index..<end])
            resolved.append(contentsOf: resolveBlock(block, format: format, headToHead: headToHead))
            index = end
        }

        var result: [StandingEntry] = []
        var position = 1
        for group in resolved {
            for var entry in group {
                entry.rank = position
                entry.isTied = group.count > 1
                result.append(entry)
            }
            position += group.count
        }
        return result
    }

    /// Orders a block of entries tied on (points, wins) into groups sharing a rank.
    private static func resolveBlock(_ block: [StandingEntry], format: TournamentFormat, headToHead: [TeamID: [TeamID: (Int, Int)]]) -> [[StandingEntry]] {
        guard block.count > 1 else { return [block] }
        if !format.isIndividual, block.count == 2,
           case .team(let x) = block[0].subject, case .team(let y) = block[1].subject,
           let h2h = headToHead[x]?[y], h2h.0 != h2h.1 {
            return h2h.0 > h2h.1 ? [[block[0]], [block[1]]] : [[block[1]], [block[0]]]
        }
        let byDifference = block.sorted { x, y in
            if x.pointDifference != y.pointDifference { return x.pointDifference > y.pointDifference }
            return x.name.localizedCaseInsensitiveCompare(y.name) == .orderedAscending
        }
        var groups: [[StandingEntry]] = []
        for entry in byDifference {
            if let last = groups.last?.last, last.pointDifference == entry.pointDifference {
                groups[groups.count - 1].append(entry)
            } else {
                groups.append([entry])
            }
        }
        return groups
    }
}
