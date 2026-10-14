import Foundation

/// Supported tournament formats.
public enum TournamentFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case americano
    case mexicano
    case mixedAmericano
    case mixicano
    case teamAmericano
    case teamMexicano
    case kingOfTheCourt

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .americano: "Americano"
        case .mexicano: "Mexicano"
        case .mixedAmericano: "Mixed Americano"
        case .mixicano: "Mixicano"
        case .teamAmericano: "Team Americano"
        case .teamMexicano: "Team Mexicano"
        case .kingOfTheCourt: "King of the Court"
        }
    }

    public var summary: String {
        switch self {
        case .americano: "Individual ranking, rotating partners"
        case .mexicano: "Pairings based on the latest standings"
        case .mixedAmericano: "Every team has one player from each group"
        case .mixicano: "Mexicano with one player from each group per team"
        case .teamAmericano: "Fixed doubles teams, team ranking"
        case .teamMexicano: "Fixed teams paired by the latest standings"
        case .kingOfTheCourt: "Winners move up a court, losers move down"
        }
    }

    /// True when standings are kept per player rather than per fixed team.
    public var isIndividual: Bool { !usesTeams }

    /// Fixed doubles teams entered before the start.
    public var usesTeams: Bool { self == .teamAmericano || self == .teamMexicano }

    /// Players belong to one of two groups and every team has one of each.
    public var usesGroups: Bool { self == .mixedAmericano || self == .mixicano }

    /// True when the whole schedule is known up front (rounds do not depend on results).
    public var hasPrecomputedSchedule: Bool {
        switch self {
        case .americano, .mixedAmericano, .teamAmericano: true
        case .mexicano, .mixicano, .teamMexicano, .kingOfTheCourt: false
        }
    }

    /// Formats whose first round can be drawn randomly or taken from the list order.
    public var hasFirstRoundOption: Bool { !hasPrecomputedSchedule }
}

/// How a single match is scored.
public enum ScoringRule: Codable, Hashable, Sendable {
    /// Rally-point match with a fixed total, e.g. 24 points shared between both teams.
    /// The match is complete exactly when the total is reached; an even total allows draws.
    case totalPoints(Int)
    /// Points are counted until the organiser ends the match after the given minutes.
    case timed(minutes: Int)
    /// Traditional games and sets (15/30/40, tie-breaks). Standings count games won.
    case sets(SetsRules)

    public static let maximumTimedPoints = 199

    public var displayName: String {
        switch self {
        case .totalPoints(let total): "\(total) points"
        case .timed(let minutes): "\(minutes) min"
        case .sets(let rules): rules.displayName
        }
    }

    public var shortDescription: String {
        switch self {
        case .totalPoints(let total): "First to \(total) total points"
        case .timed(let minutes): "Timed · \(minutes) min"
        case .sets(let rules): rules.displayName
        }
    }

    public var totalPoints: Int? {
        if case .totalPoints(let total) = self { return total }
        return nil
    }

    public var setsRules: SetsRules? {
        if case .sets(let rules) = self { return rules }
        return nil
    }

    /// True for games/sets scoring, where `Match.score` holds games won.
    public var isSets: Bool { setsRules != nil }

    /// Name of the unit counted in standings.
    public var unitName: String { isSets ? "games" : "points" }

    /// Upper bound for the combined score.
    public var maximumCombinedPoints: Int {
        switch self {
        case .totalPoints(let total): total
        case .timed: Self.maximumTimedPoints * 2
        case .sets: Int.max
        }
    }

    /// Estimated playing time for one match, used for round-count suggestions.
    public var estimatedMinutes: Int {
        switch self {
        case .totalPoints(let total): max(5, Int((Double(total) * 0.55).rounded()))
        case .timed(let minutes): minutes
        case .sets(let rules): rules.estimatedMinutes
        }
    }
}

/// Labels for the two groups used by Mixed Americano. The app never assumes what the
/// groups represent; the organiser names them.
public struct MixedGroupLabels: Codable, Hashable, Sendable {
    public var groupA: String
    public var groupB: String

    public init(groupA: String = "Group A", groupB: String = "Group B") {
        self.groupA = groupA
        self.groupB = groupB
    }

    public func label(for group: PlayerGroup) -> String {
        switch group {
        case .a: groupA
        case .b: groupB
        }
    }
}

/// Mexicano pairing pattern applied inside each block of four players sorted by rank.
public enum MexicanoPairingPattern: String, Codable, CaseIterable, Sendable {
    /// 1st & 4th vs 2nd & 3rd: the common, most balanced choice.
    case oneFourVsTwoThree
    /// 1st & 3rd vs 2nd & 4th.
    case oneThreeVsTwoFour

    public var displayName: String {
        switch self {
        case .oneFourVsTwoThree: "1 & 4 vs 2 & 3"
        case .oneThreeVsTwoFour: "1 & 3 vs 2 & 4"
        }
    }
}

/// How the first Mexicano round is arranged before any results exist.
public enum MexicanoFirstRound: String, Codable, CaseIterable, Sendable {
    /// Random but reproducible from the tournament seed.
    case random
    /// The player list order is treated as an initial ranking (strongest first).
    case listOrder

    public var displayName: String {
        switch self {
        case .random: "Random draw"
        case .listOrder: "Player list order"
        }
    }
}

/// Points credited for a round in which a player (or team) rests.
public enum RestCompensation: String, Codable, CaseIterable, Sendable {
    case none
    /// Half of the match total, i.e. the value of a draw. Only meaningful with `.totalPoints`.
    case halfMatchTotal

    public var displayName: String {
        switch self {
        case .none: "No points"
        case .halfMatchTotal: "Half the match total"
        }
    }
}

/// Complete, validated-on-creation description of the rules for one tournament.
public struct TournamentConfiguration: Codable, Hashable, Sendable {
    public var format: TournamentFormat
    public var courtCount: Int
    /// Planned number of rounds, including the final round when enabled.
    public var roundCount: Int
    public var scoring: ScoringRule
    public var mixedLabels: MixedGroupLabels
    public var mexicanoPattern: MexicanoPairingPattern
    public var mexicanoFirstRound: MexicanoFirstRound
    /// When true the last round is arranged from the standings (top players together).
    public var standingsBasedFinalRound: Bool
    public var restCompensation: RestCompensation
    /// Seed for every random choice. Same configuration + seed => same schedule.
    public var seed: UInt64

    public init(
        format: TournamentFormat = .americano,
        courtCount: Int = 2,
        roundCount: Int = 7,
        scoring: ScoringRule = .totalPoints(24),
        mixedLabels: MixedGroupLabels = MixedGroupLabels(),
        mexicanoPattern: MexicanoPairingPattern = .oneFourVsTwoThree,
        mexicanoFirstRound: MexicanoFirstRound = .random,
        standingsBasedFinalRound: Bool = false,
        restCompensation: RestCompensation = .none,
        seed: UInt64 = 1
    ) {
        self.format = format
        self.courtCount = courtCount
        self.roundCount = roundCount
        self.scoring = scoring
        self.mixedLabels = mixedLabels
        self.mexicanoPattern = mexicanoPattern
        self.mexicanoFirstRound = mexicanoFirstRound
        self.standingsBasedFinalRound = standingsBasedFinalRound
        self.restCompensation = restCompensation
        self.seed = seed
    }

    /// Points credited for a rest round under the current rules.
    public var restPoints: Int {
        switch (restCompensation, scoring) {
        case (.halfMatchTotal, .totalPoints(let total)): total / 2
        default: 0
        }
    }
}
