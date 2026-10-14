import Foundation

extension Tournament {
    /// A compact copy for the watch: event logs are kept only where the watch may still
    /// score or undo (unfinished matches and matches of the current round). Finished
    /// matches from earlier rounds keep their authoritative score without history.
    public func compactedForWatch() -> Tournament {
        var copy = self
        let current = currentRoundNumber ?? (rounds.last?.number ?? 0)
        for r in copy.rounds.indices {
            for m in copy.rounds[r].matches.indices {
                let match = copy.rounds[r].matches[m]
                if match.isCompleted && match.roundNumber < current {
                    copy.rounds[r].matches[m] = match.compacted()
                }
                copy.rounds[r].matches[m].conflicts = []
            }
        }
        copy.orphanedConflicts = []
        return copy
    }

    /// Applies an event to a local, non-authoritative copy (the watch's optimistic view).
    /// Unlike `applyRemoteEvents` this never creates or removes rounds: only the
    /// coordinating iPhone does that, so both devices can never generate competing rounds.
    @discardableResult
    public mutating func applyProvisional(_ event: ScoreEvent) -> ApplyOutcome {
        guard status == .active else { return .rejected(.tournamentCompleted) }
        guard let path = indexPath(of: event.matchID) else { return .rejected(.unknownMatch) }
        return ScoringEngine.apply(event, to: &rounds[path.round].matches[path.match], rule: configuration.scoring)
    }

    /// Whether an event ID is part of this tournament's authoritative record (applied or
    /// recorded as a conflict). Used by the watch to confirm delivery.
    public func contains(eventID: EventID) -> Bool {
        if processedRemoteEventIDs.contains(eventID) { return true }
        if orphanedConflicts.contains(where: { $0.id == eventID }) { return true }
        for match in allMatches where match.knownEventIDs.contains(eventID) { return true }
        return false
    }
}
