import Foundation

/// A single reversible change to a match. Events are identified by `id` (never by
/// timestamp) so that redelivery of the same event is harmless.
public struct ScoreEvent: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        /// One rally won by the given side.
        case point(TeamSide)
        /// Reverses the referenced point or score-set event.
        case undo(EventID)
        /// Replaces the score (manual entry or correction).
        case setScore(Score)
        /// Marks the match as finished with its current score.
        case finish
        /// Re-opens a finished match for correction.
        case reopen
    }

    public var id: EventID
    public var tournamentID: TournamentID
    public var matchID: MatchID
    public var kind: Kind
    /// Score before the event, as seen by the device that applied it.
    public var previousScore: Score
    /// Score after the event, as seen by the device that applied it.
    public var resultingScore: Score
    public var timestamp: Date
    public var deviceID: DeviceID
    /// Monotonic per-device counter. Orders events from one device.
    public var deviceSequence: Int
    /// Number of events in the match log when the event was created on its device.
    public var baseRevision: Int

    public init(
        id: EventID = EventID(),
        tournamentID: TournamentID,
        matchID: MatchID,
        kind: Kind,
        previousScore: Score = .zero,
        resultingScore: Score = .zero,
        timestamp: Date,
        deviceID: DeviceID,
        deviceSequence: Int,
        baseRevision: Int
    ) {
        self.id = id
        self.tournamentID = tournamentID
        self.matchID = matchID
        self.kind = kind
        self.previousScore = previousScore
        self.resultingScore = resultingScore
        self.timestamp = timestamp
        self.deviceID = deviceID
        self.deviceSequence = deviceSequence
        self.baseRevision = baseRevision
    }

    var changesScore: Bool {
        switch kind {
        case .point, .setScore: true
        case .undo, .finish, .reopen: false
        }
    }
}

/// Why an event could not be applied.
public enum ScoreRejection: String, Codable, Hashable, Sendable, Error, CustomStringConvertible {
    case matchCompleted
    case matchNotCompleted
    case totalReached
    case scoreExceedsRules
    case scoreIncomplete
    case undoTargetMissing
    case undoTargetAlreadyUndone
    case undoTargetNotUndoable
    case undoSupersededByCorrection
    case nothingToUndo
    case matchNotEditable
    case unknownMatch
    case unknownTournament
    case tournamentCompleted

    public var description: String {
        switch self {
        case .matchCompleted: "The match is already finished."
        case .matchNotCompleted: "The match is not finished."
        case .totalReached: "The match total has already been reached."
        case .scoreExceedsRules: "The score is not allowed by the match rules."
        case .scoreIncomplete: "The configured total has not been reached yet."
        case .undoTargetMissing: "The point to undo was not found."
        case .undoTargetAlreadyUndone: "That point was already undone."
        case .undoTargetNotUndoable: "Only points and score changes can be undone."
        case .undoSupersededByCorrection: "The score was corrected after that point."
        case .nothingToUndo: "There is nothing to undo."
        case .matchNotEditable: "This match can only be edited on the iPhone."
        case .unknownMatch: "The match no longer exists in this tournament."
        case .unknownTournament: "The tournament no longer exists."
        case .tournamentCompleted: "The tournament is finished. Reopen it to make changes."
        }
    }
}

/// A received event that was not applied. Kept for review, never silently dropped.
public struct ScoreConflict: Codable, Hashable, Sendable, Identifiable {
    public var event: ScoreEvent
    public var reason: ScoreRejection
    public var recordedAt: Date
    public var isAcknowledged: Bool

    public var id: EventID { event.id }

    public init(event: ScoreEvent, reason: ScoreRejection, recordedAt: Date, isAcknowledged: Bool = false) {
        self.event = event
        self.reason = reason
        self.recordedAt = recordedAt
        self.isAcknowledged = isAcknowledged
    }
}

public enum ApplyOutcome: Equatable, Sendable {
    case applied
    /// The event was seen before (applied or recorded as a conflict). Nothing changed.
    case duplicate
    case rejected(ScoreRejection)
}

/// The single domain-level scoring operation. Every score change, local or remote,
/// goes through `apply`, which validates the event against the rules and the current
/// state, appends it, and recomputes the cached score from the full log.
public enum ScoringEngine {
    public struct ReplayResult: Equatable, Sendable {
        public var score: Score
        public var status: MatchStatus
        public var completedAt: Date?
    }

    /// Rebuilds the match state from its log. The log is the single source of truth.
    public static func replay(_ log: [ScoreEvent]) -> ReplayResult {
        let undone = undoneEventIDs(in: log)
        var score = Score.zero
        var completed = false
        var completedAt: Date?
        for event in log where !undone.contains(event.id) {
            switch event.kind {
            case .point(let side): score[side] += 1
            case .setScore(let newScore): score = newScore
            case .finish:
                completed = true
                completedAt = event.timestamp
            case .reopen:
                completed = false
                completedAt = nil
            case .undo: break
            }
        }
        let status: MatchStatus = completed ? .completed : (log.isEmpty ? .scheduled : .inProgress)
        return ReplayResult(score: score, status: status, completedAt: completedAt)
    }

    static func undoneEventIDs(in log: [ScoreEvent]) -> Set<EventID> {
        var ids = Set<EventID>()
        for event in log {
            if case .undo(let target) = event.kind { ids.insert(target) }
        }
        return ids
    }

    /// The most recent score-changing event that has not been undone.
    public static func lastUndoableEvent(in match: Match) -> ScoreEvent? {
        guard !match.isCompleted, !match.isLogCompacted else { return nil }
        let undone = undoneEventIDs(in: match.log)
        return match.log.last { $0.changesScore && !undone.contains($0.id) }
    }

    /// Checks whether `kind` may be applied to `match` under `rule`, without mutating.
    public static func validate(_ kind: ScoreEvent.Kind, on match: Match, rule: ScoringRule) -> ScoreRejection? {
        if match.isLogCompacted { return .matchNotEditable }
        switch kind {
        case .point:
            if match.isCompleted { return .matchCompleted }
            if match.score.total >= rule.maximumCombinedPoints { return .totalReached }
            if case .timed = rule, match.score.a >= ScoringRule.maximumTimedPoints || match.score.b >= ScoringRule.maximumTimedPoints {
                return .scoreExceedsRules
            }
            return nil
        case .setScore(let score):
            if match.isCompleted { return .matchCompleted }
            return validateScoreValue(score, rule: rule)
        case .finish:
            if match.isCompleted { return .matchCompleted }
            if let total = rule.totalPoints, match.score.total != total { return .scoreIncomplete }
            return nil
        case .reopen:
            return match.isCompleted ? nil : .matchNotCompleted
        case .undo(let target):
            if match.isCompleted { return .matchCompleted }
            guard let index = match.log.firstIndex(where: { $0.id == target }) else { return .undoTargetMissing }
            let targetEvent = match.log[index]
            guard targetEvent.changesScore else { return .undoTargetNotUndoable }
            let undone = undoneEventIDs(in: match.log)
            if undone.contains(target) { return .undoTargetAlreadyUndone }
            if case .point = targetEvent.kind {
                // Undoing a point that precedes an effective score correction would have no
                // visible effect, which is never what the user intended.
                let later = match.log[(index + 1)...]
                if later.contains(where: { if case .setScore = $0.kind { return !undone.contains($0.id) } else { return false } }) {
                    return .undoSupersededByCorrection
                }
            }
            return nil
        }
    }

    /// Validates a score value (used for manual entry and corrections).
    public static func validateScoreValue(_ score: Score, rule: ScoringRule) -> ScoreRejection? {
        if score.a < 0 || score.b < 0 { return .scoreExceedsRules }
        switch rule {
        case .totalPoints(let total):
            if score.total > total { return .scoreExceedsRules }
        case .timed:
            if score.a > ScoringRule.maximumTimedPoints || score.b > ScoringRule.maximumTimedPoints { return .scoreExceedsRules }
        }
        return nil
    }

    /// Validates a final result for a completed match.
    public static func validateFinalScore(_ score: Score, rule: ScoringRule) -> ScoreRejection? {
        if let rejection = validateScoreValue(score, rule: rule) { return rejection }
        if let total = rule.totalPoints, score.total != total { return .scoreIncomplete }
        return nil
    }

    /// Applies an event idempotently. On success the stored copy carries the authoritative
    /// previous/resulting scores. Rejected events are *not* recorded here; callers that
    /// receive remote events record them with `recordConflict`.
    @discardableResult
    public static func apply(_ event: ScoreEvent, to match: inout Match, rule: ScoringRule) -> ApplyOutcome {
        if match.knownEventIDs.contains(event.id) { return .duplicate }
        if let rejection = validate(event.kind, on: match, rule: rule) { return .rejected(rejection) }
        var stored = event
        stored.previousScore = match.score
        var newLog = match.log
        newLog.append(stored)
        let result = replay(newLog)
        newLog[newLog.count - 1].resultingScore = result.score
        match.log = newLog
        match.score = result.score
        match.status = result.status
        match.completedAt = result.completedAt
        return .applied
    }

    /// Keeps a rejected remote event for later review.
    public static func recordConflict(_ event: ScoreEvent, reason: ScoreRejection, in match: inout Match, at date: Date) {
        guard !match.knownEventIDs.contains(event.id) else { return }
        match.conflicts.append(ScoreConflict(event: event, reason: reason, recordedAt: date))
    }

    public static func acknowledgeConflicts(in match: inout Match) {
        for index in match.conflicts.indices { match.conflicts[index].isAcknowledged = true }
    }

    /// Recomputes cached state from the log. Returns true when the cache was wrong
    /// (e.g. a file edited by hand or written by an older buggy build).
    @discardableResult
    public static func repairCache(_ match: inout Match) -> Bool {
        guard !match.isLogCompacted else { return false }
        let result = replay(match.log)
        let wrong = result.score != match.score || result.status != match.status
        match.score = result.score
        match.status = result.status
        match.completedAt = result.completedAt
        return wrong
    }

    /// Whether the match can be finished right now.
    public static func canFinish(_ match: Match, rule: ScoringRule) -> Bool {
        validate(.finish, on: match, rule: rule) == nil
    }

    /// True when a fixed-total match has reached its total but has not been finished.
    public static func isAwaitingConfirmation(_ match: Match, rule: ScoringRule) -> Bool {
        guard !match.isCompleted, let total = rule.totalPoints else { return false }
        return match.score.total == total
    }
}
