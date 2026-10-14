import Foundation

public struct ValidationIssue: Hashable, Sendable, Identifiable {
    public enum Severity: String, Sendable { case error, warning }

    public enum Code: String, Sendable {
        case missingName
        case tooFewPlayers
        case tooManyPlayers
        case emptyPlayerName
        case duplicatePlayerName
        case duplicatePlayerID
        case invalidCourtCount
        case unusedCourts
        case invalidRoundCount
        case invalidPoints
        case invalidDuration
        case missingGroup
        case groupTooSmall
        case unevenGroups
        case tooFewTeams
        case invalidTeam
        case playerInTwoTeams
        case duplicateTeamName
        case finalRoundNeedsMoreRounds
        case restCompensationNeedsTotalPoints
        case oddRestPoints
        case manyRests
    }

    public var severity: Severity
    public var code: Code
    public var message: String
    public var suggestion: String?

    public var id: String { code.rawValue + message }

    public init(severity: Severity, code: Code, message: String, suggestion: String? = nil) {
        self.severity = severity
        self.code = code
        self.message = message
        self.suggestion = suggestion
    }
}

public struct TournamentDraft: Sendable, Hashable {
    public var name: String
    public var configuration: TournamentConfiguration
    public var players: [Player]
    public var teams: [Team]

    public init(name: String, configuration: TournamentConfiguration, players: [Player], teams: [Team] = []) {
        self.name = name
        self.configuration = configuration
        self.players = players
        self.teams = teams
    }
}

public enum ConfigurationValidator {
    public static let minimumPoints = 4
    public static let maximumPoints = 99
    public static let maximumPlayers = 64
    public static let maximumCourts = 16
    public static let maximumRounds = 40

    public static func validate(_ draft: TournamentDraft) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let config = draft.configuration
        func error(_ code: ValidationIssue.Code, _ message: String, _ suggestion: String? = nil) {
            issues.append(ValidationIssue(severity: .error, code: code, message: message, suggestion: suggestion))
        }
        func warning(_ code: ValidationIssue.Code, _ message: String, _ suggestion: String? = nil) {
            issues.append(ValidationIssue(severity: .warning, code: code, message: message, suggestion: suggestion))
        }

        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error(.missingName, "Give the tournament a name.")
        }

        // Players
        let players = draft.players
        if Set(players.map(\.id)).count != players.count {
            error(.duplicatePlayerID, "The same player appears twice in the list.")
        }
        if players.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            error(.emptyPlayerName, "Every player needs a name.")
        }
        var seenNames: [String: String] = [:]
        for player in players {
            let key = player.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            if seenNames[key] != nil {
                error(.duplicatePlayerName, "Two players are called \(player.name).", "Add an initial, e.g. \(player.name) B.")
                break
            }
            seenNames[key] = player.name
        }
        if players.count > maximumPlayers {
            error(.tooManyPlayers, "Up to \(maximumPlayers) players are supported.")
        }

        // Courts
        if config.courtCount < 1 || config.courtCount > maximumCourts {
            error(.invalidCourtCount, "Choose between 1 and \(maximumCourts) courts.")
        }

        // Rounds
        if config.roundCount < 1 || config.roundCount > maximumRounds {
            error(.invalidRoundCount, "Choose between 1 and \(maximumRounds) rounds.")
        }
        if config.standingsBasedFinalRound && config.roundCount < 2 {
            error(.finalRoundNeedsMoreRounds, "A final round needs at least one round before it.", "Increase the rounds to 2 or more.")
        }

        // Scoring
        switch config.scoring {
        case .totalPoints(let total):
            if total < minimumPoints || total > maximumPoints {
                error(.invalidPoints, "Points per match must be between \(minimumPoints) and \(maximumPoints).")
            }
        case .timed(let minutes):
            if minutes < 3 || minutes > 90 {
                error(.invalidDuration, "Match duration must be between 3 and 90 minutes.")
            }
            if config.restCompensation != .none {
                error(.restCompensationNeedsTotalPoints, "Rest points are only available with a fixed points total.", "Turn off rest points or use a points total.")
            }
        }

        // Format specific
        switch config.format {
        case .americano, .mexicano:
            if players.count < 4 {
                error(.tooFewPlayers, "\(config.format.displayName) needs at least 4 players. You have \(players.count).", "Add \(4 - players.count) more.")
            }
        case .mixedAmericano:
            if players.contains(where: { $0.group == nil }) {
                error(.missingGroup, "Assign every player to \(config.mixedLabels.groupA) or \(config.mixedLabels.groupB).")
            }
            let a = players.filter { $0.group == .a }.count
            let b = players.filter { $0.group == .b }.count
            if a < 2 || b < 2 {
                error(.groupTooSmall,
                      "Mixed Americano needs at least 2 players in each group (\(config.mixedLabels.groupA): \(a), \(config.mixedLabels.groupB): \(b)).",
                      "Every team has one player from each group.")
            } else if a != b {
                let larger = a > b ? config.mixedLabels.groupA : config.mixedLabels.groupB
                warning(.unevenGroups, "\(config.mixedLabels.groupA) has \(a) and \(config.mixedLabels.groupB) has \(b) players. \(larger) players will rest more often.",
                        "Balance the groups for equal playing time.")
            }
        case .teamAmericano:
            validateTeams(draft, error: error)
        }

        // Capacity
        if !issues.contains(where: { $0.severity == .error }) {
            let usable = Capacity.matchesPerRound(format: config.format, courts: config.courtCount, players: players, teamCount: draft.teams.count)
            if usable < config.courtCount {
                let unit = config.format == .teamAmericano ? "teams" : "players"
                warning(.unusedCourts,
                        "Only \(usable) of \(config.courtCount) courts can be used with these \(unit).",
                        "Use \(usable) court\(usable == 1 ? "" : "s"), or add more \(unit).")
            }
            let participants = config.format == .teamAmericano ? draft.teams.count : players.count
            let perRound = config.format == .teamAmericano ? usable * 2 : usable * 4
            let resting = participants - perRound
            if resting > 0 && perRound > 0 && resting * 2 > participants {
                warning(.manyRests, "\(resting) of \(participants) will rest each round.", "Add a court if you have one.")
            }
        }

        if case .totalPoints(let total) = config.scoring, total % 2 == 1, config.restCompensation == .halfMatchTotal {
            warning(.oddRestPoints, "With an odd total, rest points are rounded down to \(total / 2).")
        }
        return issues
    }

    private static func validateTeams(_ draft: TournamentDraft, error: (ValidationIssue.Code, String, String?) -> Void) {
        let teams = draft.teams
        if teams.count < 2 {
            error(.tooFewTeams, "Team Americano needs at least 2 teams. You have \(teams.count).", "Add \(2 - teams.count) more team\(teams.count == 1 ? "" : "s").")
        }
        let playerIDs = Set(draft.players.map(\.id))
        var used = Set<PlayerID>()
        var names = Set<String>()
        for team in teams {
            if team.playerIDs.count != 2 || Set(team.playerIDs).count != 2 || !team.playerIDs.allSatisfy(playerIDs.contains) {
                error(.invalidTeam, "\(team.name.isEmpty ? "A team" : team.name) needs two different players.", nil)
            }
            for id in team.playerIDs {
                if used.contains(id) {
                    let name = draft.players.first { $0.id == id }?.name ?? "A player"
                    error(.playerInTwoTeams, "\(name) is in two teams.", "Each player can only be in one team.")
                }
                used.insert(id)
            }
            let key = team.name.trimmingCharacters(in: .whitespaces).lowercased()
            if !key.isEmpty && names.contains(key) {
                error(.duplicateTeamName, "Two teams are called \(team.name).", nil)
            }
            names.insert(key)
        }
    }

    public static func errors(_ draft: TournamentDraft) -> [ValidationIssue] {
        validate(draft).filter { $0.severity == .error }
    }
}

/// Helpers for picking a sensible number of rounds.
public enum RoundPlanner {
    /// Rounds needed for every possible partnership (individual) or pairing (teams) to
    /// occur at least once, given court capacity. Capped to keep evenings realistic.
    public static func fullRotationRounds(format: TournamentFormat, players: [Player], teamCount: Int, courts: Int) -> Int {
        let matches = Capacity.matchesPerRound(format: format, courts: courts, players: players, teamCount: teamCount)
        guard matches > 0 else { return 1 }
        let rounds: Int
        switch format {
        case .americano, .mexicano:
            let n = players.count
            let partnerships = n * (n - 1) / 2
            rounds = Int((Double(partnerships) / Double(2 * matches)).rounded(.up))
        case .mixedAmericano:
            let a = players.filter { $0.group == .a }.count
            let b = players.filter { $0.group == .b }.count
            rounds = Int((Double(a * b) / Double(2 * matches)).rounded(.up))
        case .teamAmericano:
            let pairings = teamCount * (teamCount - 1) / 2
            rounds = Int((Double(pairings) / Double(matches)).rounded(.up))
        }
        return max(1, min(rounds, ConfigurationValidator.maximumRounds))
    }

    /// A default that completes a rotation where practical but fits a typical evening.
    public static func recommendedRounds(format: TournamentFormat, players: [Player], teamCount: Int, courts: Int, scoring: ScoringRule, availableMinutes: Int = 120) -> Int {
        let full = fullRotationRounds(format: format, players: players, teamCount: teamCount, courts: courts)
        let fitting = max(1, availableMinutes / minutesPerRound(scoring))
        let rounds = format == .mexicano ? min(fitting, 8) : min(full, fitting)
        return max(1, rounds)
    }

    public static func minutesPerRound(_ scoring: ScoringRule) -> Int {
        scoring.estimatedMinutes + 3
    }

    public static func estimatedMinutes(rounds: Int, scoring: ScoringRule) -> Int {
        rounds * minutesPerRound(scoring)
    }

    /// Rounds that fit in the given time.
    public static func rounds(fitting minutes: Int, scoring: ScoringRule) -> Int {
        max(1, minutes / minutesPerRound(scoring))
    }
}
