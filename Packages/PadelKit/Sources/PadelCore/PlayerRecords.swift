import Foundation

// Player statistics across every tournament on the device.
//
// There are no accounts: a person is recognised by name. Names are compared trimmed,
// with runs of spaces collapsed, ignoring case, accents and character width, so "José",
// " jose " and "JOSE" are the same player. Two people with the same name are therefore
// counted as one; the first name typed into a tournament is what the organiser sees, so
// they already tell namesakes apart there (the player editor asks for an initial).
//
// Everything is derived from saved results, like the standings: nothing is stored.

/// Identity of a player across tournaments: the normalised name.
public struct PlayerKey: Hashable, Comparable, Sendable, Codable {
    public let rawValue: String

    public init(name: String) {
        rawValue = PlayerRecords.normalize(name)
    }

    public static func < (lhs: PlayerKey, rhs: PlayerKey) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Result of one completed match from one player's point of view.
public enum MatchOutcome: String, Sendable, Hashable, Codable {
    case win, draw, loss
}

/// How a player did with (partner) or against (opponent) another player.
public struct PlayerRelation: Sendable, Hashable {
    public var key: PlayerKey
    /// Most recent spelling of the other player's name.
    public var name: String
    public var matches: Int
    /// Wins, draws and losses of the player the record belongs to.
    public var wins: Int
    public var draws: Int
    public var losses: Int
}

/// One tournament in a player's history.
public struct PlayerTournamentRecord: Sendable, Hashable, Identifiable {
    public var tournamentID: TournamentID
    public var tournamentName: String
    public var date: Date
    public var format: TournamentFormat
    /// True for games-and-sets tournaments: `scoredFor/Against` are games, not points.
    public var countsGames: Bool
    public var isCompleted: Bool
    /// Final position (current position while the tournament is still running). With a
    /// decided playoff: 1 champions, 2 runners-up, 3 semifinal losers, 5 quarterfinal
    /// losers; everybody else keeps their standings position. Nil if not ranked.
    public var rank: Int?
    public var isTied: Bool
    public var matchesPlayed: Int
    public var wins: Int
    public var draws: Int
    public var losses: Int
    public var scoredFor: Int
    public var scoredAgainst: Int

    public var id: TournamentID { tournamentID }
    /// First place in a completed tournament.
    public var isWin: Bool { isCompleted && rank == 1 }
    /// Top three in a completed tournament.
    public var isPodium: Bool { isCompleted && (rank ?? .max) <= 3 }
}

/// A player's statistics across all tournaments.
public struct PlayerRecord: Sendable, Hashable, Identifiable {
    public var key: PlayerKey
    /// Most recent spelling of the name.
    public var name: String
    public var tournamentWins: Int
    public var podiums: Int
    public var matchesPlayed: Int
    public var wins: Int
    public var draws: Int
    public var losses: Int
    /// Points in rally-point and timed tournaments.
    public var pointsFor: Int
    public var pointsAgainst: Int
    /// Games in games-and-sets tournaments.
    public var gamesFor: Int
    public var gamesAgainst: Int
    /// The partner with the most wins together (then most matches together). Nil when the
    /// player has not won with anybody yet.
    public var bestPartner: PlayerRelation?
    /// The opponent faced most often.
    public var mostFrequentOpponent: PlayerRelation?
    /// Up to the last five results, oldest first.
    public var form: [MatchOutcome]
    /// Tournaments with at least one completed match for this player, newest first.
    public var tournaments: [PlayerTournamentRecord]

    public var id: PlayerKey { key }
    public var tournamentsPlayed: Int { tournaments.count }
    /// Share of matches won (draws count as not won); nil before the first match.
    public var winRate: Double? { matchesPlayed > 0 ? Double(wins) / Double(matchesPlayed) : nil }
}

public enum PlayerRecordOrder: String, CaseIterable, Sendable, Hashable {
    /// Matches won, then tournament wins.
    case wins
    case winRate
    case matches
}

public enum PlayerRecords {
    public static let formLength = 5

    /// Trimmed, single-spaced, case-, accent- and width-insensitive form of a name.
    public static func normalize(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        return words.joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Records for every player with at least one completed match, ordered by name.
    public static func compute(_ tournaments: [Tournament]) -> [PlayerRecord] {
        var accumulators: [PlayerKey: Accumulator] = [:]
        // Oldest first, so the latest spelling of a name wins and form is chronological.
        let ordered = tournaments.sorted {
            $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id < $1.id
        }
        for tournament in ordered {
            accumulate(tournament, into: &accumulators)
        }
        return accumulators.values
            .map { $0.record() }
            .sorted { $0.key < $1.key }
    }

    /// The record of one player, or nil when they have no completed match.
    public static func record(for key: PlayerKey, in tournaments: [Tournament]) -> PlayerRecord? {
        compute(tournaments).first { $0.key == key }
    }

    public static func sorted(_ records: [PlayerRecord], by order: PlayerRecordOrder) -> [PlayerRecord] {
        records.sorted { x, y in
            let xRate = x.winRate ?? -1, yRate = y.winRate ?? -1
            switch order {
            case .wins:
                if x.wins != y.wins { return x.wins > y.wins }
                if x.tournamentWins != y.tournamentWins { return x.tournamentWins > y.tournamentWins }
                if xRate != yRate { return xRate > yRate }
            case .winRate:
                if xRate != yRate { return xRate > yRate }
                if x.matchesPlayed != y.matchesPlayed { return x.matchesPlayed > y.matchesPlayed }
            case .matches:
                if x.matchesPlayed != y.matchesPlayed { return x.matchesPlayed > y.matchesPlayed }
                if x.wins != y.wins { return x.wins > y.wins }
            }
            return x.key < y.key
        }
    }

    /// Records whose name contains the query (same normalisation as names).
    public static func filter(_ records: [PlayerRecord], query: String) -> [PlayerRecord] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return records }
        return records.filter { $0.key.rawValue.contains(needle) }
    }

    /// Final (or current) position of every player in one tournament. Team formats give
    /// both team members the team's position; a decided playoff overrides the standings
    /// for the teams that reached it.
    public static func placements(in tournament: Tournament) -> [PlayerID: (rank: Int, isTied: Bool)] {
        var result: [PlayerID: (rank: Int, isTied: Bool)] = [:]
        let standings = StandingsCalculator.compute(tournament)
        for entry in standings.entries {
            switch entry.subject {
            case .player(let id):
                result[id] = (entry.rank, entry.isTied)
            case .team(let id):
                for player in tournament.team(id)?.playerIDs ?? [] { result[player] = (entry.rank, entry.isTied) }
            }
        }
        guard tournament.playoffChampion != nil else { return result }
        for round in tournament.rounds {
            guard let stage = tournament.knockoutStage(of: round) else { continue }
            if stage == .final, let final = round.matches.first, let winner = ScoringEngine.winner(of: final) {
                for player in final.side(winner).playerIDs { result[player] = (1, false) }
                for player in final.side(winner.opposite).playerIDs { result[player] = (2, false) }
                continue
            }
            let losers = round.matches.compactMap { match -> MatchSide? in
                guard match.isCompleted, let winner = ScoringEngine.winner(of: match) else { return nil }
                return match.side(winner.opposite)
            }
            for side in losers {
                for player in side.playerIDs { result[player] = (stage.rawValue / 2 + 1, losers.count > 1) }
            }
        }
        return result
    }

    // MARK: Accumulation

    private struct RelationCount {
        var name: String
        var matches = 0
        var wins = 0
        var draws = 0
        var losses = 0

        mutating func add(_ outcome: MatchOutcome) {
            matches += 1
            switch outcome {
            case .win: wins += 1
            case .draw: draws += 1
            case .loss: losses += 1
            }
        }

        func relation(_ key: PlayerKey) -> PlayerRelation {
            PlayerRelation(key: key, name: name, matches: matches, wins: wins, draws: draws, losses: losses)
        }
    }

    /// One player's matches in one tournament.
    private struct Tally {
        var played = 0
        var wins = 0
        var draws = 0
        var losses = 0
        var scored = 0
        var conceded = 0

        mutating func add(_ outcome: MatchOutcome, scored points: Int, conceded against: Int) {
            played += 1
            switch outcome {
            case .win: wins += 1
            case .draw: draws += 1
            case .loss: losses += 1
            }
            scored += points
            conceded += against
        }
    }

    private struct Accumulator {
        var key: PlayerKey
        var name: String
        var wins = 0
        var draws = 0
        var losses = 0
        var pointsFor = 0
        var pointsAgainst = 0
        var gamesFor = 0
        var gamesAgainst = 0
        var outcomes: [MatchOutcome] = []
        var partners: [PlayerKey: RelationCount] = [:]
        var opponents: [PlayerKey: RelationCount] = [:]
        var tournaments: [PlayerTournamentRecord] = []

        func record() -> PlayerRecord {
            let best = partners
                .filter { $0.value.wins > 0 }
                .max { x, y in
                    if x.value.wins != y.value.wins { return x.value.wins < y.value.wins }
                    if x.value.matches != y.value.matches { return x.value.matches < y.value.matches }
                    return x.key > y.key
                }
            let rival = opponents.max { x, y in
                if x.value.matches != y.value.matches { return x.value.matches < y.value.matches }
                return x.key > y.key
            }
            let history = tournaments.reversed()
            return PlayerRecord(
                key: key,
                name: name,
                tournamentWins: history.filter(\.isWin).count,
                podiums: history.filter(\.isPodium).count,
                matchesPlayed: wins + draws + losses,
                wins: wins,
                draws: draws,
                losses: losses,
                pointsFor: pointsFor,
                pointsAgainst: pointsAgainst,
                gamesFor: gamesFor,
                gamesAgainst: gamesAgainst,
                bestPartner: best.map { $0.value.relation($0.key) },
                mostFrequentOpponent: rival.map { $0.value.relation($0.key) },
                form: Array(outcomes.suffix(PlayerRecords.formLength)),
                tournaments: Array(history)
            )
        }
    }

    private static func accumulate(_ tournament: Tournament, into accumulators: inout [PlayerKey: Accumulator]) {
        var keys: [PlayerID: PlayerKey] = [:]
        var names: [PlayerID: String] = [:]
        for player in tournament.players {
            let key = PlayerKey(name: player.name)
            guard !key.rawValue.isEmpty else { continue }
            keys[player.id] = key
            names[player.id] = player.name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }

        var perTournament: [PlayerKey: Tally] = [:]
        var playerIDsByKey: [PlayerKey: [PlayerID]] = [:]
        let countsGames = tournament.configuration.scoring.isSets

        let rounds = tournament.rounds.sorted { $0.number < $1.number }
        for round in rounds {
            for match in round.matches.sorted(by: { $0.court < $1.court }) where match.isCompleted {
                // Unplayed matches (including a withdrawn player's) never count.
                let winner = ScoringEngine.winner(of: match)
                let games = tournament.scoringRule(for: match).isSets
                for side in TeamSide.allCases {
                    let outcome: MatchOutcome = winner == side ? .win : (winner == side.opposite ? .loss : .draw)
                    let mine = match.score[side], theirs = match.score[side.opposite]
                    let teammates = match.side(side).playerIDs
                    let opponents = match.side(side.opposite).playerIDs
                    for playerID in teammates {
                        guard let key = keys[playerID], let name = names[playerID] else { continue }
                        var accumulator = accumulators[key] ?? Accumulator(key: key, name: name)
                        accumulator.name = name
                        switch outcome {
                        case .win: accumulator.wins += 1
                        case .draw: accumulator.draws += 1
                        case .loss: accumulator.losses += 1
                        }
                        if games {
                            accumulator.gamesFor += mine
                            accumulator.gamesAgainst += theirs
                        } else {
                            accumulator.pointsFor += mine
                            accumulator.pointsAgainst += theirs
                        }
                        accumulator.outcomes.append(outcome)
                        for partnerID in teammates where partnerID != playerID {
                            guard let partnerKey = keys[partnerID], partnerKey != key, let partnerName = names[partnerID] else { continue }
                            accumulator.partners[partnerKey, default: RelationCount(name: partnerName)].name = partnerName
                            accumulator.partners[partnerKey]?.add(outcome)
                        }
                        for opponentID in opponents {
                            guard let opponentKey = keys[opponentID], opponentKey != key, let opponentName = names[opponentID] else { continue }
                            accumulator.opponents[opponentKey, default: RelationCount(name: opponentName)].name = opponentName
                            accumulator.opponents[opponentKey]?.add(outcome)
                        }
                        accumulators[key] = accumulator

                        perTournament[key, default: Tally()].add(outcome, scored: mine, conceded: theirs)
                        if !(playerIDsByKey[key]?.contains(playerID) ?? false) { playerIDsByKey[key, default: []].append(playerID) }
                    }
                }
            }
        }

        guard !perTournament.isEmpty else { return }
        let positions = placements(in: tournament)
        for (key, entry) in perTournament {
            // Namesakes inside one tournament share a record; take the better position.
            let placement = (playerIDsByKey[key] ?? [])
                .compactMap { positions[$0] }
                .min { $0.rank < $1.rank }
            accumulators[key]?.tournaments.append(PlayerTournamentRecord(
                tournamentID: tournament.id,
                tournamentName: tournament.name,
                date: tournament.createdAt,
                format: tournament.configuration.format,
                countsGames: countsGames,
                isCompleted: tournament.status == .completed,
                rank: placement?.rank,
                isTied: placement?.isTied ?? false,
                matchesPlayed: entry.played,
                wins: entry.wins,
                draws: entry.draws,
                losses: entry.losses,
                scoredFor: entry.scored,
                scoredAgainst: entry.conceded
            ))
        }
    }
}
