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
        case invalidSetsRules
        case playoffAndFinalRound
        case notEnoughForPlayoff
        case singleCourtLadder
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
            error(.missingName, L10n.string("Give the tournament a name."))
        }

        // Players
        let players = draft.players
        if Set(players.map(\.id)).count != players.count {
            error(.duplicatePlayerID, L10n.string("The same player appears twice in the list."))
        }
        if players.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            error(.emptyPlayerName, L10n.string("Every player needs a name."))
        }
        var seenNames: [String: String] = [:]
        for player in players {
            let key = player.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            if seenNames[key] != nil {
                error(.duplicatePlayerName, L10n.format("Two players are called %@.", player.name), L10n.format("Add an initial, e.g. %@ B.", player.name))
                break
            }
            seenNames[key] = player.name
        }
        if players.count > maximumPlayers {
            error(.tooManyPlayers, L10n.format("Up to %lld players are supported.", maximumPlayers))
        }

        // Courts
        if config.courtCount < 1 || config.courtCount > maximumCourts {
            error(.invalidCourtCount, L10n.format("Choose between 1 and %lld courts.", maximumCourts))
        }

        // Rounds
        if config.roundCount < 1 || config.roundCount > maximumRounds {
            error(.invalidRoundCount, L10n.format("Choose between 1 and %lld rounds.", maximumRounds))
        }
        if config.playoff != .none {
            if config.standingsBasedFinalRound {
                error(.playoffAndFinalRound, L10n.string("Choose either a final round from the standings or playoffs, not both."))
            }
            let qualifiers = config.playoff.teamCount
            let available: Int
            if config.format.usesTeams {
                available = draft.teams.count
            } else if config.format.usesGroups {
                available = min(players.filter { $0.group == .a }.count, players.filter { $0.group == .b }.count)
            } else {
                available = players.count / 2
            }
            if available < qualifiers {
                error(.notEnoughForPlayoff,
                      config.format.usesTeams
                        ? L10n.format("%@ needs %lld teams but only %lld can be formed.", config.playoff.displayName, qualifiers, available)
                        : L10n.format("%@ needs %lld pairs but only %lld can be formed.", config.playoff.displayName, qualifiers, available),
                      L10n.string("Choose a smaller playoff."))
            }
        }
        if config.standingsBasedFinalRound && config.roundCount < 2 {
            error(.finalRoundNeedsMoreRounds, L10n.string("A final round needs at least one round before it."), L10n.string("Increase the rounds to 2 or more."))
        }

        // Scoring
        switch config.scoring {
        case .totalPoints(let total):
            if total < minimumPoints || total > maximumPoints {
                error(.invalidPoints, L10n.format("Points per match must be between %lld and %lld.", minimumPoints, maximumPoints))
            }
        case .timed(let minutes):
            if minutes < 3 || minutes > 90 {
                error(.invalidDuration, L10n.string("Match duration must be between 3 and 90 minutes."))
            }
            if config.restCompensation != .none {
                error(.restCompensationNeedsTotalPoints, L10n.string("Rest points are only available with a fixed points total."), L10n.string("Turn off rest points or use a points total."))
            }
        case .sets(let rules):
            if !rules.isValid {
                error(.invalidSetsRules, L10n.string("Choose 1 to 3 sets to win and 2 to 9 games per set."))
            }
            if config.restCompensation != .none {
                error(.restCompensationNeedsTotalPoints, L10n.string("Rest points are only available with a fixed points total."), L10n.string("Turn off rest points or use a points total."))
            }
        }

        // Format specific
        switch config.format {
        case .americano, .mexicano, .kingOfTheCourt:
            if players.count < 4 {
                error(.tooFewPlayers, L10n.format("%@ needs at least 4 players. You have %lld.", config.format.displayName, players.count), L10n.format("Add %lld more.", 4 - players.count))
            }
            if config.format == .kingOfTheCourt && config.courtCount < 2 && players.count >= 4 {
                warning(.singleCourtLadder, L10n.string("With one court, King of the Court has no courts to move between."), L10n.string("Use 2 or more courts, or choose Americano."))
            }
        case .mixedAmericano, .mixicano:
            if players.contains(where: { $0.group == nil }) {
                error(.missingGroup, L10n.format("Assign every player to %@ or %@.", config.mixedLabels.groupA, config.mixedLabels.groupB))
            }
            let a = players.filter { $0.group == .a }.count
            let b = players.filter { $0.group == .b }.count
            if a < 2 || b < 2 {
                error(.groupTooSmall,
                      L10n.format("%@ needs at least 2 players in each group (%@: %lld, %@: %lld).", config.format.displayName, config.mixedLabels.groupA, a, config.mixedLabels.groupB, b),
                      L10n.string("Every team has one player from each group."))
            } else if a != b {
                let larger = a > b ? config.mixedLabels.groupA : config.mixedLabels.groupB
                warning(.unevenGroups, L10n.format("%@ has %lld and %@ has %lld players. %@ players will rest more often.", config.mixedLabels.groupA, a, config.mixedLabels.groupB, b, larger),
                        L10n.string("Balance the groups for equal playing time."))
            }
        case .teamAmericano, .teamMexicano, .swiss:
            validateTeams(draft, error: error)
        }

        // Capacity
        if !issues.contains(where: { $0.severity == .error }) {
            let usable = Capacity.matchesPerRound(format: config.format, courts: config.courtCount, players: players, teamCount: draft.teams.count)
            if usable < config.courtCount {
                if config.format.usesTeams {
                    warning(.unusedCourts,
                            L10n.format("Only %lld of %lld courts can be used with these teams.", usable, config.courtCount),
                            L10n.format("Use %lld courts, or add more teams.", usable))
                } else {
                    warning(.unusedCourts,
                            L10n.format("Only %lld of %lld courts can be used with these players.", usable, config.courtCount),
                            L10n.format("Use %lld courts, or add more players.", usable))
                }
            }
            let participants = config.format.usesTeams ? draft.teams.count : players.count
            let perRound = config.format.usesTeams ? usable * 2 : usable * 4
            let resting = participants - perRound
            if resting > 0 && perRound > 0 && resting * 2 > participants {
                warning(.manyRests, L10n.format("%lld of %lld will rest each round.", resting, participants), L10n.string("Add a court if you have one."))
            }
        }

        if case .totalPoints(let total) = config.scoring, total % 2 == 1, config.restCompensation == .halfMatchTotal {
            warning(.oddRestPoints, L10n.format("With an odd total, rest points are rounded down to %lld.", total / 2))
        }
        return issues
    }

    private static func validateTeams(_ draft: TournamentDraft, error: (ValidationIssue.Code, String, String?) -> Void) {
        let teams = draft.teams
        if teams.count < 2 {
            error(.tooFewTeams, L10n.format("%@ needs at least 2 teams. You have %lld.", draft.configuration.format.displayName, teams.count), L10n.format("Add %lld more teams.", 2 - teams.count))
        }
        let playerIDs = Set(draft.players.map(\.id))
        var used = Set<PlayerID>()
        var names = Set<String>()
        for team in teams {
            if team.playerIDs.count != 2 || Set(team.playerIDs).count != 2 || !team.playerIDs.allSatisfy(playerIDs.contains) {
                error(.invalidTeam, team.name.isEmpty ? L10n.string("A team needs two different players.") : L10n.format("%@ needs two different players.", team.name), nil)
            }
            for id in team.playerIDs {
                if used.contains(id) {
                    let name = draft.players.first { $0.id == id }?.name ?? L10n.string("A player")
                    error(.playerInTwoTeams, L10n.format("%@ is in two teams.", name), L10n.string("Each player can only be in one team."))
                }
                used.insert(id)
            }
            let key = team.name.trimmingCharacters(in: .whitespaces).lowercased()
            if !key.isEmpty && names.contains(key) {
                error(.duplicateTeamName, L10n.format("Two teams are called %@.", team.name), nil)
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
        case .americano, .mexicano, .kingOfTheCourt:
            let n = players.count
            let partnerships = n * (n - 1) / 2
            rounds = Int((Double(partnerships) / Double(2 * matches)).rounded(.up))
        case .mixedAmericano, .mixicano:
            let a = players.filter { $0.group == .a }.count
            let b = players.filter { $0.group == .b }.count
            rounds = Int((Double(a * b) / Double(2 * matches)).rounded(.up))
        case .teamAmericano, .teamMexicano:
            let pairings = teamCount * (teamCount - 1) / 2
            rounds = Int((Double(pairings) / Double(matches)).rounded(.up))
        case .swiss:
            // log2(teams) rounds separate the field; one more settles the top places.
            rounds = Int(ceil(log2(Double(max(2, teamCount))))) + 1
        }
        return max(1, min(rounds, ConfigurationValidator.maximumRounds))
    }

    /// A default that completes a rotation where practical but fits a typical evening.
    public static func recommendedRounds(format: TournamentFormat, players: [Player], teamCount: Int, courts: Int, scoring: ScoringRule, availableMinutes: Int = 120) -> Int {
        let full = fullRotationRounds(format: format, players: players, teamCount: teamCount, courts: courts)
        let fitting = max(1, availableMinutes / minutesPerRound(scoring))
        let rounds = format.hasPrecomputedSchedule || format == .swiss ? min(full, fitting) : min(fitting, 8)
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
