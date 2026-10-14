import Foundation
import PadelCore

/// Everything the watch must remember to keep scoring offline. Persisted after every
/// change, before anything is sent.
///
/// Model: the last authoritative snapshot from the iPhone, plus an outbox of locally
/// recorded events not yet acknowledged. The watch's view is the snapshot with the
/// outbox replayed on top (optimistic). When a newer snapshot arrives, acknowledged
/// events leave the outbox and the rest are replayed again (rebase).
public struct WatchSyncState: Codable, Hashable, Sendable {
    public static let maximumPendingEvents = 2_000

    public var deviceID: DeviceID
    public private(set) var snapshot: WatchSnapshot?
    /// Unacknowledged local events, in recording order.
    public private(set) var pending: [ScoreEvent]
    public private(set) var nextSequence: Int
    public private(set) var lastAcknowledgedAt: Date?
    /// Tournaments with the outbox applied. Derived; kept in sync by `rebuildView()`.
    public private(set) var view: [Tournament]
    /// Pending events that could not be applied to the latest snapshot (e.g. the match
    /// was finished on the iPhone). They stay in the outbox until the iPhone records
    /// them (as conflicts), so nothing is lost.
    public private(set) var unappliedPendingIDs: [EventID]

    public init(deviceID: DeviceID) {
        self.deviceID = deviceID
        self.snapshot = nil
        self.pending = []
        self.nextSequence = 1
        self.lastAcknowledgedAt = nil
        self.view = []
        self.unappliedPendingIDs = []
    }

    public enum WatchError: Error, Equatable, Sendable {
        case unknownTournament
        case unknownMatch
        case rejected(ScoreRejection)
        case outboxFull
    }

    public func tournament(_ id: TournamentID) -> Tournament? {
        view.first { $0.id == id }
    }

    public var hasPending: Bool { !pending.isEmpty }

    // MARK: Recording

    /// Validates and records an event against the local view.
    @discardableResult
    public mutating func record(_ kind: ScoreEvent.Kind, matchID: MatchID, tournamentID: TournamentID, now: Date, eventID: EventID = EventID()) throws(WatchError) -> ScoreEvent {
        guard pending.count < Self.maximumPendingEvents else { throw .outboxFull }
        guard let index = view.firstIndex(where: { $0.id == tournamentID }) else { throw .unknownTournament }
        guard let match = view[index].match(matchID) else { throw .unknownMatch }
        let event = ScoreEvent(
            id: eventID,
            tournamentID: tournamentID,
            matchID: matchID,
            kind: kind,
            previousScore: match.score,
            resultingScore: match.score,
            timestamp: now,
            deviceID: deviceID,
            deviceSequence: nextSequence,
            baseRevision: match.log.count
        )
        var tournament = view[index]
        switch tournament.applyProvisional(event) {
        case .applied:
            break
        case .duplicate:
            throw .rejected(.undoTargetAlreadyUndone)
        case .rejected(let reason):
            throw .rejected(reason)
        }
        let stored = tournament.match(matchID)?.log.last ?? event
        view[index] = tournament
        pending.append(stored)
        nextSequence += 1
        return stored
    }

    @discardableResult
    public mutating func recordPoint(_ side: TeamSide, matchID: MatchID, tournamentID: TournamentID, now: Date) throws(WatchError) -> ScoreEvent {
        try record(.point(side), matchID: matchID, tournamentID: tournamentID, now: now)
    }

    @discardableResult
    public mutating func undoLast(matchID: MatchID, tournamentID: TournamentID, now: Date) throws(WatchError) -> ScoreEvent {
        guard let match = tournament(tournamentID)?.match(matchID) else { throw .unknownMatch }
        guard let target = ScoringEngine.lastUndoableEvent(in: match) else {
            throw .rejected(match.isCompleted ? .matchCompleted : .nothingToUndo)
        }
        return try record(.undo(target.id), matchID: matchID, tournamentID: tournamentID, now: now)
    }

    // MARK: Synchronisation

    public enum SnapshotOutcome: Equatable, Sendable {
        case accepted(acknowledged: Int)
        case stale
    }

    /// Accepts a newer authoritative snapshot, drops acknowledged events from the outbox
    /// and replays the rest. Older snapshots are ignored so they can never overwrite
    /// newer results.
    @discardableResult
    public mutating func receive(_ newSnapshot: WatchSnapshot, now: Date) -> SnapshotOutcome {
        guard newSnapshot.schemaVersion <= WatchSnapshot.currentSchemaVersion, newSnapshot.supersedes(snapshot) else {
            return .stale
        }
        snapshot = newSnapshot
        let before = pending.count
        pending.removeAll { newSnapshot.acknowledges($0.id) }
        let acknowledged = before - pending.count
        if acknowledged > 0 { lastAcknowledgedAt = now }
        rebuildView()
        return .accepted(acknowledged: acknowledged)
    }

    /// The batch to send: every pending event, oldest first.
    public func outgoingBatch(now: Date) -> EventBatch? {
        pending.isEmpty ? nil : EventBatch(deviceID: deviceID, events: pending, sentAt: now)
    }

    mutating func rebuildView() {
        var tournaments = snapshot?.tournaments ?? []
        var unapplied: [EventID] = []
        for event in pending {
            guard let index = tournaments.firstIndex(where: { $0.id == event.tournamentID }) else {
                unapplied.append(event.id)
                continue
            }
            switch tournaments[index].applyProvisional(event) {
            case .applied, .duplicate: break
            case .rejected: unapplied.append(event.id)
            }
        }
        view = tournaments
        unappliedPendingIDs = unapplied
    }
}
