import Foundation

/// Measurable fairness of a schedule. Used by tests and shown to organisers.
public struct ScheduleMetrics: Sendable, Equatable {
    /// Σ max(0, times partnered − 1) over all pairs (individual formats).
    public var partnerRepeats: Int
    public var maxTimesPartnered: Int
    /// Number of distinct partnerships that occurred.
    public var distinctPartnerships: Int
    /// Σ max(0, times opposed − 1) over all pairs of players (or teams).
    public var opponentRepeats: Int
    public var maxTimesOpposed: Int
    /// max − min matches played among participants present for the whole schedule.
    public var playedSpread: Int
    public var restSpread: Int
    public var consecutiveRests: Int
    public var minPlayed: Int
    public var maxPlayed: Int

    public static func individual(rounds: [Round], participants: [PlayerID]) -> ScheduleMetrics {
        let history = PlayerHistory.players(from: rounds)
        let played = participants.map { history.playedCount($0) }
        let rested = participants.map { history.restCount($0) }
        return ScheduleMetrics(
            partnerRepeats: history.partners.repeats,
            maxTimesPartnered: history.partners.maximum,
            distinctPartnerships: history.partners.distinctPairs,
            opponentRepeats: history.opponents.repeats,
            maxTimesOpposed: history.opponents.maximum,
            playedSpread: (played.max() ?? 0) - (played.min() ?? 0),
            restSpread: (rested.max() ?? 0) - (rested.min() ?? 0),
            consecutiveRests: history.consecutiveRestViolations,
            minPlayed: played.min() ?? 0,
            maxPlayed: played.max() ?? 0
        )
    }

    public static func team(rounds: [Round], participants: [TeamID]) -> ScheduleMetrics {
        let history = TeamHistory.teams(from: rounds)
        let played = participants.map { history.playedCount($0) }
        let rested = participants.map { history.restCount($0) }
        return ScheduleMetrics(
            partnerRepeats: 0,
            maxTimesPartnered: 0,
            distinctPartnerships: 0,
            opponentRepeats: history.opponents.repeats,
            maxTimesOpposed: history.opponents.maximum,
            playedSpread: (played.max() ?? 0) - (played.min() ?? 0),
            restSpread: (rested.max() ?? 0) - (rested.min() ?? 0),
            consecutiveRests: history.consecutiveRestViolations,
            minPlayed: played.min() ?? 0,
            maxPlayed: played.max() ?? 0
        )
    }

    public static func of(_ tournament: Tournament) -> ScheduleMetrics {
        if tournament.configuration.format.isIndividual {
            return individual(rounds: tournament.rounds, participants: tournament.activePlayers.map(\.id))
        }
        return team(rounds: tournament.rounds, participants: tournament.activeTeams.map(\.id))
    }
}
