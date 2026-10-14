import Foundation

public enum PlayerGroup: String, Codable, CaseIterable, Sendable, Hashable {
    case a
    case b
}

public struct Player: Codable, Hashable, Identifiable, Sendable {
    public var id: PlayerID
    public var name: String
    /// Only used by Mixed Americano. `nil` for every other format.
    public var group: PlayerGroup?

    public init(id: PlayerID = PlayerID(), name: String, group: PlayerGroup? = nil) {
        self.id = id
        self.name = name
        self.group = group
    }

    /// One or two letters for avatars.
    public var initials: String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "-" }).prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

public struct Team: Codable, Hashable, Identifiable, Sendable {
    public var id: TeamID
    public var name: String
    public var playerIDs: [PlayerID]

    public init(id: TeamID = TeamID(), name: String, playerIDs: [PlayerID]) {
        self.id = id
        self.name = name
        self.playerIDs = playerIDs
    }
}

/// One of the two sides of a match.
public enum TeamSide: String, Codable, CaseIterable, Sendable, Hashable {
    case a
    case b

    public var opposite: TeamSide { self == .a ? .b : .a }
}

/// The players (and, for fixed-team formats, the team) on one side of a match.
public struct MatchSide: Codable, Hashable, Sendable {
    public var playerIDs: [PlayerID]
    public var teamID: TeamID?

    public init(playerIDs: [PlayerID], teamID: TeamID? = nil) {
        self.playerIDs = playerIDs
        self.teamID = teamID
    }
}

public struct Score: Codable, Hashable, Sendable, CustomStringConvertible {
    public var a: Int
    public var b: Int

    public init(a: Int = 0, b: Int = 0) {
        self.a = a
        self.b = b
    }

    public static let zero = Score()

    public var total: Int { a + b }

    public subscript(side: TeamSide) -> Int {
        get { side == .a ? a : b }
        set { if side == .a { a = newValue } else { b = newValue } }
    }

    public var winner: TeamSide? {
        if a > b { return .a }
        if b > a { return .b }
        return nil
    }

    public var description: String { "\(a)–\(b)" }
}

public enum MatchStatus: String, Codable, Sendable, Hashable {
    case scheduled
    case inProgress
    case completed
}

public struct Match: Codable, Hashable, Identifiable, Sendable {
    public var id: MatchID
    public var roundNumber: Int
    public var court: Int
    public var sideA: MatchSide
    public var sideB: MatchSide

    /// Authoritative, append-only history of accepted score events.
    public internal(set) var log: [ScoreEvent]
    /// Events that were received but could not be applied. Never silently discarded.
    public internal(set) var conflicts: [ScoreConflict]

    // Cached projection of `log`. Recomputed by `ScoringEngine` whenever the log changes.
    public internal(set) var score: Score
    public internal(set) var status: MatchStatus
    public internal(set) var completedAt: Date?
    /// True when the log was stripped (watch snapshots of finished matches). The cached
    /// score is then authoritative and the match cannot be edited locally.
    public internal(set) var isLogCompacted: Bool

    public init(id: MatchID = MatchID(), roundNumber: Int, court: Int, sideA: MatchSide, sideB: MatchSide) {
        self.id = id
        self.roundNumber = roundNumber
        self.court = court
        self.sideA = sideA
        self.sideB = sideB
        self.log = []
        self.conflicts = []
        self.score = .zero
        self.status = .scheduled
        self.completedAt = nil
        self.isLogCompacted = false
    }

    public func side(_ side: TeamSide) -> MatchSide {
        side == .a ? sideA : sideB
    }

    public var allPlayerIDs: [PlayerID] { sideA.playerIDs + sideB.playerIDs }

    public func side(of player: PlayerID) -> TeamSide? {
        if sideA.playerIDs.contains(player) { return .a }
        if sideB.playerIDs.contains(player) { return .b }
        return nil
    }

    public func side(ofTeam team: TeamID) -> TeamSide? {
        if sideA.teamID == team { return .a }
        if sideB.teamID == team { return .b }
        return nil
    }

    public var isCompleted: Bool { status == .completed }
    public var hasStarted: Bool { status != .scheduled }
    /// Conflicts the organiser has not reviewed yet.
    public var openConflicts: [ScoreConflict] { conflicts.filter { !$0.isAcknowledged } }

    /// Every event ID this match has seen, applied or rejected. Used for deduplication.
    public var knownEventIDs: Set<EventID> {
        var ids = Set(log.map(\.id))
        for conflict in conflicts { ids.insert(conflict.event.id) }
        return ids
    }

    /// Removes the event history, keeping the cached result. Used for compact snapshots.
    public func compacted() -> Match {
        var copy = self
        copy.log = []
        copy.isLogCompacted = true
        return copy
    }

    /// Reset to an unplayed state. Only the tournament engine uses this (restart).
    mutating func resetResult() {
        log = []
        conflicts = []
        score = .zero
        status = .scheduled
        completedAt = nil
        isLogCompacted = false
    }
}

public enum RoundKind: String, Codable, Sendable, Hashable {
    case regular
    /// Arranged from the standings so the top players meet.
    case final
}

public enum RoundStatus: String, Sendable, Hashable {
    case upcoming
    case inProgress
    case completed
}

public struct Round: Codable, Hashable, Sendable, Identifiable {
    public var number: Int
    public var kind: RoundKind
    public var matches: [Match]
    public var restingPlayerIDs: [PlayerID]
    public var restingTeamIDs: [TeamID]

    public var id: Int { number }

    public init(number: Int, kind: RoundKind = .regular, matches: [Match], restingPlayerIDs: [PlayerID] = [], restingTeamIDs: [TeamID] = []) {
        self.number = number
        self.kind = kind
        self.matches = matches
        self.restingPlayerIDs = restingPlayerIDs
        self.restingTeamIDs = restingTeamIDs
    }

    public var status: RoundStatus {
        if !matches.isEmpty && matches.allSatisfy(\.isCompleted) { return .completed }
        if matches.contains(where: \.hasStarted) { return .inProgress }
        return .upcoming
    }

    public var hasStarted: Bool { matches.contains(where: \.hasStarted) }
    public var isCompleted: Bool { status == .completed }
}

public enum TournamentStatus: String, Codable, Sendable, Hashable {
    case active
    case completed
}

/// The aggregate root. Everything about one tournament lives here and is saved atomically.
public struct Tournament: Codable, Hashable, Identifiable, Sendable {
    public var id: TournamentID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var configuration: TournamentConfiguration
    /// Every player that ever took part, including withdrawn ones (history needs them).
    public var players: [Player]
    public var teams: [Team]
    public var withdrawnPlayerIDs: [PlayerID]
    public var withdrawnTeamIDs: [TeamID]
    public internal(set) var rounds: [Round]
    public internal(set) var status: TournamentStatus
    public internal(set) var completedAt: Date?
    /// Incremented on every change. Used to detect stale snapshots.
    public internal(set) var revision: Int
    /// Most recent remote event IDs that were processed (applied or recorded as conflicts).
    /// Bounded; sent back to the watch as acknowledgements.
    public internal(set) var processedRemoteEventIDs: [EventID]
    /// Remote events whose match no longer exists (e.g. a rebuilt round). Kept for review.
    public internal(set) var orphanedConflicts: [ScoreConflict]

    public static let processedRemoteEventLimit = 600

    public init(
        id: TournamentID = TournamentID(),
        name: String,
        createdAt: Date,
        configuration: TournamentConfiguration,
        players: [Player],
        teams: [Team] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.configuration = configuration
        self.players = players
        self.teams = teams
        self.withdrawnPlayerIDs = []
        self.withdrawnTeamIDs = []
        self.rounds = []
        self.status = .active
        self.completedAt = nil
        self.revision = 0
        self.processedRemoteEventIDs = []
        self.orphanedConflicts = []
    }

    // MARK: Lookup

    public func player(_ id: PlayerID) -> Player? { players.first { $0.id == id } }
    public func team(_ id: TeamID) -> Team? { teams.first { $0.id == id } }

    public func playerName(_ id: PlayerID) -> String { player(id)?.name ?? "Unknown" }

    public var activePlayers: [Player] {
        players.filter { !withdrawnPlayerIDs.contains($0.id) }
    }

    public var activeTeams: [Team] {
        teams.filter { !withdrawnTeamIDs.contains($0.id) }
    }

    public var allMatches: [Match] { rounds.flatMap(\.matches) }

    public func match(_ id: MatchID) -> Match? {
        for round in rounds {
            if let match = round.matches.first(where: { $0.id == id }) { return match }
        }
        return nil
    }

    func indexPath(of matchID: MatchID) -> (round: Int, match: Int)? {
        for (r, round) in rounds.enumerated() {
            if let m = round.matches.firstIndex(where: { $0.id == matchID }) { return (r, m) }
        }
        return nil
    }

    /// Display name for one side of a match: team name for fixed teams, else "Alex & Johan".
    public func sideName(_ side: MatchSide) -> String {
        if let teamID = side.teamID, let team = team(teamID) { return team.name }
        return side.playerIDs.map { playerName($0) }.joined(separator: " & ")
    }

    public func sideName(of match: Match, _ side: TeamSide) -> String {
        sideName(match.side(side))
    }

    // MARK: Progress

    /// The first round that is not completed, or `nil` when every generated round is done.
    public var currentRound: Round? { rounds.first { !$0.isCompleted } }

    public var currentRoundNumber: Int? { currentRound?.number }

    public var completedRoundCount: Int { rounds.filter(\.isCompleted).count }

    /// All planned rounds have been generated and completed.
    public var allRoundsCompleted: Bool {
        rounds.count >= configuration.roundCount && rounds.allSatisfy(\.isCompleted)
    }

    public var hasAnyResult: Bool { rounds.contains(where: \.hasStarted) }

    /// Matches currently being played (started, not completed).
    public var liveMatches: [Match] { allMatches.filter { $0.status == .inProgress } }

    public var openConflictCount: Int {
        allMatches.reduce(0) { $0 + $1.openConflicts.count } + orphanedConflicts.filter { !$0.isAcknowledged }.count
    }
}
