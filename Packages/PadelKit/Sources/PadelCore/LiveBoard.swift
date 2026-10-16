import Foundation

/// What the public spectator page (`docs/live`) shows for one tournament: standings,
/// the courts of the current round and the playoff result. Players' and teams' names,
/// scores and the tournament's name only — nothing else leaves the phone.
///
/// The organiser publishes it (as compact JSON) while "Share Live Leaderboard" is on.
/// The JSON keys are short and stable; the web page reads exactly these.
public struct LiveBoardSnapshot: Codable, Hashable, Sendable {
    /// Bump when the page has to tell layouts apart.
    public static let currentVersion = 1

    public struct Standing: Codable, Hashable, Sendable {
        public var rank: Int
        /// Another row shares the rank (shown as "=2").
        public var tied: Bool
        public var name: String
        public var points: Int
        public var won: Int
        public var drawn: Int
        public var lost: Int
        public var difference: Int

        enum CodingKeys: String, CodingKey {
            case rank, tied, name
            case points = "pts"
            case won = "w"
            case drawn = "d"
            case lost = "l"
            case difference = "diff"
        }
    }

    public enum CourtState: String, Codable, Hashable, Sendable {
        case live
        case upcoming
        case finished
    }

    public struct Court: Codable, Hashable, Sendable {
        public var court: Int
        public var state: CourtState
        public var teamA: String
        public var teamB: String
        /// Big figures: points, or the current game's points (15, 30, 40, Ad) in games
        /// and sets scoring. Empty before the match starts.
        public var scoreA: String
        public var scoreB: String
        /// Games and sets so far ("6-4 3-2"); nil for rally points and timed matches.
        public var sets: String?

        enum CodingKeys: String, CodingKey {
            case court, state, sets
            case teamA = "a"
            case teamB = "b"
            case scoreA = "sa"
            case scoreB = "sb"
        }
    }

    /// Which kind of round is being played.
    public enum Stage: String, Codable, Hashable, Sendable {
        case regular
        /// The standings-based final round (not a knockout).
        case finalRound
        case quarterfinal
        case semifinal
        case final
    }

    public var version: Int
    public var name: String
    /// `TournamentFormat` raw value.
    public var format: String
    /// The format's name in the organiser's language.
    public var formatName: String
    public var status: TournamentStatus
    /// The round being played (the last round once everything is played).
    public var round: Int
    /// Planned rounds, playoff stages included.
    public var rounds: Int
    public var stage: Stage
    /// True when standings count games (games and sets scoring) instead of points.
    public var countsGames: Bool
    public var standings: [Standing]
    /// The current round's matches by court. Empty once the tournament is finished.
    public var courts: [Court]
    /// Players resting this round.
    public var resting: [String]
    public var champion: String?
    public var runnerUp: String?
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case name, format, formatName, status, round, rounds, stage, standings, courts, resting, champion, runnerUp, updatedAt
        case countsGames = "games"
    }

    public init(tournament: Tournament, updatedAt: Date) {
        let configuration = tournament.configuration
        version = Self.currentVersion
        name = tournament.name
        format = configuration.format.rawValue
        formatName = configuration.format.displayName
        status = tournament.status
        rounds = max(configuration.totalRoundCount, tournament.rounds.count)
        countsGames = configuration.scoring.isSets
        self.updatedAt = updatedAt

        let current = tournament.status == .active ? tournament.currentRound : nil
        let shown = current ?? tournament.rounds.last
        round = shown?.number ?? 0
        if let shown, let knockout = tournament.knockoutStage(of: shown) {
            switch knockout {
            case .final: stage = .final
            case .semifinal: stage = .semifinal
            case .quarterfinal: stage = .quarterfinal
            }
        } else {
            stage = shown?.kind == .final ? .finalRound : .regular
        }

        standings = StandingsCalculator.compute(tournament).entries.map { entry in
            Standing(rank: entry.rank, tied: entry.isTied, name: entry.name, points: entry.points, won: entry.wins, drawn: entry.draws, lost: entry.losses, difference: entry.pointDifference)
        }

        if let current {
            courts = current.matches.sorted { $0.court < $1.court }.map { Self.court($0, in: tournament) }
            resting = configuration.format.isIndividual
                ? current.restingPlayerIDs.map { tournament.playerName($0) }
                : current.restingTeamIDs.compactMap { tournament.team($0)?.name }
        } else {
            courts = []
            resting = []
        }

        champion = tournament.playoffChampion.map { tournament.sideName($0) }
        runnerUp = tournament.playoffRunnerUp.map { tournament.sideName($0) }
    }

    private static func court(_ match: Match, in tournament: Tournament) -> Court {
        let state: CourtState = match.isCompleted ? .finished : (match.hasStarted ? .live : .upcoming)
        var court = Court(court: match.court, state: state, teamA: tournament.sideName(match.sideA), teamB: tournament.sideName(match.sideB), scoreA: "", scoreB: "", sets: nil)
        guard match.hasStarted else { return court }
        if case .sets(let rules) = tournament.scoringRule(for: match), let sets = match.sets {
            if sets.isDecided || match.isCompleted {
                court.scoreA = "\(sets.setsWon.a)"
                court.scoreB = "\(sets.setsWon.b)"
            } else {
                court.scoreA = sets.pointLabel(.a, rules: rules)
                court.scoreB = sets.pointLabel(.b, rules: rules)
            }
            let summary = sets.summary()
            court.sets = summary.isEmpty ? nil : summary
        } else {
            court.scoreA = "\(match.score.a)"
            court.scoreB = "\(match.score.b)"
        }
        return court
    }

    /// The same board at another time; used to tell whether anything visible changed.
    public func at(_ date: Date) -> LiveBoardSnapshot {
        var copy = self
        copy.updatedAt = date
        return copy
    }

    // MARK: JSON

    public func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    public static func decode(_ json: String) throws -> LiveBoardSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LiveBoardSnapshot.self, from: Data(json.utf8))
    }
}

/// The spectator link.
public enum LiveBoard {
    /// The static page in `docs/live`, served by GitHub Pages.
    public static let pageURL = URL(string: "https://wrexist.github.io/PadelOS/live/")!

    /// Tokens are base62, so they fit a URL fragment and a CloudKit record name as-is.
    public static let tokenAlphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    /// 24 base62 characters ≈ 143 bits: not guessable.
    public static let tokenLength = 24

    /// `https://wrexist.github.io/PadelOS/live/#<token>`
    public static func url(token: String) -> URL {
        URL(string: pageURL.absoluteString + "#" + token)!
    }

    public static func isValidToken(_ token: String) -> Bool {
        token.count >= 22 && token.count <= 64 && token.allSatisfy { tokenAlphabet.contains($0) }
    }
}

extension Tournament {
    /// Organiser: turns the spectator board on (a token) or off (`nil`). Like sharing,
    /// this is not a change to the tournament itself, so `revision` stays put.
    public mutating func setLiveBoardToken(_ token: String?) throws(TournamentError) {
        guard !isGuest else { throw .notAllowed(L10n.string("Only the organiser can change this tournament.")) }
        liveBoardToken = token
    }

    /// The spectator link while the board is shared.
    public var liveBoardURL: URL? { liveBoardToken.map(LiveBoard.url(token:)) }
}
