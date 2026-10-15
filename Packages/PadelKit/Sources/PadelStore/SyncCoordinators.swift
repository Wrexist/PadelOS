import Foundation
import Observation
import PadelCore
import PadelSync

/// Connects the iPhone's store to the watch. The iPhone is the authority: it applies
/// watch events, saves, and only then publishes a snapshot that acknowledges them.
@MainActor
@Observable
public final class PhoneSyncCoordinator {
    public private(set) var lastPublishedSequence: Int = 0
    public private(set) var lastEventReceivedAt: Date?
    public private(set) var lastError: String?

    @ObservationIgnored private let store: TournamentStore
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let transport: SyncTransport
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var lastSnapshot: WatchSnapshot?

    public init(store: TournamentStore, settings: SettingsStore, transport: SyncTransport, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.settings = settings
        self.transport = transport
        self.now = now
    }

    public var isWatchReachable: Bool { transport.isReachable }

    public func start() {
        transport.onReceive = { [weak self] message, reply in
            self?.handle(message, reply: reply)
        }
        transport.onStateChange = { [weak self] in
            self?.publish()
        }
        store.onChange = { [weak self] in
            self?.publish()
        }
        transport.activate()
        publish()
    }

    /// Sends the latest authoritative state as the application context.
    @discardableResult
    public func publish() -> WatchSnapshot {
        let snapshot = WatchSnapshot.make(
            from: store.tournaments,
            phoneInstanceID: settings.settings.phoneInstanceID,
            sequence: settings.nextSyncSequence(),
            now: now(),
            extraAcknowledged: settings.settings.unroutableEvents.suffix(100).map(\.id)
        )
        lastSnapshot = snapshot
        lastPublishedSequence = snapshot.sequence
        do {
            try transport.updateLatestState(.snapshot(snapshot))
        } catch {
            lastError = error.localizedDescription
        }
        return snapshot
    }

    func handle(_ message: SyncMessage, reply: ((SyncMessage) -> Void)?) {
        switch message {
        case .eventBatch(let batch):
            lastEventReceivedAt = now()
            let result = store.applyRemote(batch)
            // Unroutable events are stored before they are acknowledged.
            settings.recordUnroutable(result.unroutable)
            if let error = result.error {
                // Nothing unsaved is acknowledged; the watch keeps the events and retries.
                lastError = error.localizedDescription
            }
            let snapshot = result.changed && lastSnapshot != nil && result.unroutable.isEmpty ? lastSnapshot! : publish()
            reply?(.snapshot(snapshot))
        case .snapshotRequest:
            reply?(.snapshot(publish()))
        case .snapshot:
            break // The phone is authoritative and never adopts a snapshot.
        }
    }
}

/// Watch-side state container: offline scoring with a durable outbox.
@MainActor
@Observable
public final class WatchStore {
    public enum SyncStatus: Equatable, Sendable {
        /// No tournament data received from the iPhone yet.
        case waitingForPhone
        /// Everything recorded on the watch has been saved on the iPhone.
        case upToDate
        /// Events are stored on the watch and will be sent when possible.
        case pending(count: Int, reachable: Bool)
    }

    public private(set) var state: WatchSyncState
    public private(set) var lastError: String?
    public private(set) var isReachable = false

    @ObservationIgnored private let file: JSONFileStore<WatchSyncState>?
    @ObservationIgnored private let transport: SyncTransport?
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(file: JSONFileStore<WatchSyncState>?, transport: SyncTransport?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.file = file
        self.transport = transport
        self.now = now
        var loaded: WatchSyncState?
        do {
            loaded = try file?.load()
        } catch {
            lastError = error.description
        }
        state = loaded ?? WatchSyncState(deviceID: DeviceID())
    }

    public static func defaultFile() -> JSONFileStore<WatchSyncState> {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return JSONFileStore(url: base.appendingPathComponent("WatchState.json"), schemaVersion: 1)
    }

    public var tournaments: [Tournament] { state.view }

    public var syncStatus: SyncStatus {
        if state.snapshot == nil && state.pending.isEmpty { return .waitingForPhone }
        if state.pending.isEmpty { return .upToDate }
        return .pending(count: state.pending.count, reachable: isReachable)
    }

    public func start() {
        transport?.onReceive = { [weak self] message, _ in
            self?.receive(message)
        }
        transport?.onStateChange = { [weak self] in
            guard let self else { return }
            self.isReachable = self.transport?.isReachable ?? false
            self.flush()
            if self.state.snapshot == nil { self.requestSnapshot() }
        }
        transport?.activate()
        isReachable = transport?.isReachable ?? false
        flush()
    }

    // MARK: Scoring

    /// Records a point. Returns false when the action was not allowed.
    @discardableResult
    public func recordPoint(_ side: TeamSide, match: MatchID, tournament: TournamentID) -> Bool {
        commit { (state, now) throws(WatchSyncState.WatchError) in try state.recordPoint(side, matchID: match, tournamentID: tournament, now: now) }
    }

    @discardableResult
    public func undo(match: MatchID, tournament: TournamentID) -> Bool {
        commit { (state, now) throws(WatchSyncState.WatchError) in try state.undoLast(matchID: match, tournamentID: tournament, now: now) }
    }

    @discardableResult
    public func finish(match: MatchID, tournament: TournamentID) -> Bool {
        commit { (state, now) throws(WatchSyncState.WatchError) in try state.record(.finish, matchID: match, tournamentID: tournament, now: now) }
    }

    @discardableResult
    public func reopen(match: MatchID, tournament: TournamentID) -> Bool {
        commit { (state, now) throws(WatchSyncState.WatchError) in try state.record(.reopen, matchID: match, tournamentID: tournament, now: now) }
    }

    /// Mutate → save → publish → send. A failed save leaves the previous state intact.
    private func commit(_ change: (inout WatchSyncState, Date) throws(WatchSyncState.WatchError) -> ScoreEvent) -> Bool {
        var copy = state
        do {
            _ = try change(&copy, now())
        } catch {
            lastError = Self.describe(error)
            return false
        }
        do {
            try file?.save(copy, now: now())
        } catch {
            lastError = error.description
            return false
        }
        state = copy
        lastError = nil
        flush()
        return true
    }

    static func describe(_ error: WatchSyncState.WatchError) -> String {
        switch error {
        case .unknownTournament: L10n.string("This tournament is no longer on the watch.")
        case .unknownMatch: L10n.string("This match is no longer in the schedule.")
        case .rejected(let reason): reason.description
        case .outboxFull: L10n.string("Too many unsent points. Open the iPhone app to sync.")
        }
    }

    // MARK: Sync

    /// Sends every pending event: immediately when the iPhone is reachable (the reply
    /// acknowledges), otherwise as one durable transfer that replaces older ones.
    public func flush() {
        guard let transport, let batch = state.outgoingBatch(now: now()) else { return }
        let message = SyncMessage.eventBatch(batch)
        if transport.isReachable {
            transport.sendImmediate(message, reply: { [weak self] response in
                self?.receive(response)
            }, failure: { [weak self] _ in
                guard let self, let latest = self.state.outgoingBatch(now: self.now()) else { return }
                self.transport?.enqueueDurable(.eventBatch(latest), replacingPending: true)
            })
        } else {
            transport.enqueueDurable(message, replacingPending: true)
        }
    }

    public func requestSnapshot() {
        transport?.sendImmediate(.snapshotRequest(state.deviceID), reply: { [weak self] response in
            self?.receive(response)
        }, failure: nil)
    }

    public func receive(_ message: SyncMessage) {
        guard case .snapshot(let snapshot) = message else { return }
        var copy = state
        guard case .accepted = copy.receive(snapshot, now: now()) else { return }
        do {
            try file?.save(copy, now: now())
        } catch {
            // Keep the new state in memory; the snapshot will be delivered again.
            lastError = error.description
        }
        state = copy
    }
}
