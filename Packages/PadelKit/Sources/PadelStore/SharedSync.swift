import Foundation
import Observation
import PadelCore
import PadelSync

/// Where one shared tournament lives in the cloud.
public struct SharedZone: Hashable, Sendable {
    public var name: String
    public var owner: String
    /// True on the organiser's phone (the zone is in its own database).
    public var isOwnedByThisDevice: Bool

    public init(name: String, owner: String, isOwnedByThisDevice: Bool) {
        self.name = name
        self.owner = owner
        self.isOwnedByThisDevice = isOwnedByThisDevice
    }

    public init(_ info: SharingInfo) {
        self.init(name: info.zoneName, owner: info.zoneOwner, isOwnedByThisDevice: info.role == .host)
    }

    var key: String { "\(owner)/\(name)" }
}

/// What changed in a zone since the last fetch.
public struct SharedZoneChanges: Sendable {
    /// The newest organiser state in the zone, if it changed.
    public var tournament: Tournament?
    /// Score events waiting for the organiser.
    public var events: [ScoreEvent]
    /// Opaque position to fetch from next time.
    public var token: Data?

    public init(tournament: Tournament? = nil, events: [ScoreEvent] = [], token: Data? = nil) {
        self.tournament = tournament
        self.events = events
        self.token = token
    }
}

public enum SharingError: Error, Equatable, Sendable, LocalizedError {
    case noAccount
    case zoneMissing
    case tooLarge
    case organiserOnly
    case notFound
    case service(String)

    public var errorDescription: String? {
        switch self {
        case .noAccount: L10n.string("Sign in to iCloud in Settings to share tournaments.")
        case .zoneMissing: L10n.string("The organiser stopped sharing this tournament.")
        case .tooLarge: L10n.string("This tournament is too large to share.")
        case .organiserOnly: L10n.string("Only the organiser can invite players.")
        case .notFound: L10n.string("This tournament no longer exists.")
        case .service(let message): message
        }
    }
}

/// The cloud storage a shared tournament needs. CloudKit in the apps, in memory in tests.
public protocol SharedTournamentBackend: Sendable {
    /// Creates the zone with the tournament and an invitation; returns the zone and link.
    func share(_ tournament: Tournament) async throws -> (zone: SharedZone, url: URL)
    /// The invitation link of a zone this device owns.
    func invitationURL(for zone: SharedZone) async throws -> URL?
    func changes(in zone: SharedZone, since token: Data?) async throws -> SharedZoneChanges
    func publish(_ tournament: Tournament, in zone: SharedZone) async throws
    /// Uploads events; returns the IDs that were stored.
    func upload(_ events: [ScoreEvent], to zone: SharedZone) async throws -> [EventID]
    func removeEvents(_ ids: [EventID], from zone: SharedZone) async throws
    /// Host: stops sharing. Guest: leaves the share.
    func removeZone(_ zone: SharedZone) async throws
    /// Asks the cloud to wake this device with a silent push whenever a zone in one
    /// database changes: the zones this device owns (organiser: guests uploaded events)
    /// or the zones shared with it (guest: the organiser published). Idempotent.
    func subscribeToChanges(ownedByThisDevice: Bool) async throws
}

/// Keeps shared tournaments in step between phones.
///
/// Organiser (host): pulls the score events other phones uploaded, applies them through
/// the same path as watch events (dedupe, validate, conflicts), saves, then publishes its
/// state and removes the events it has recorded.
/// Guest: adopts the newest organiser state (its own unconfirmed events replayed on top)
/// and uploads the events the organiser has not recorded yet.
@MainActor
@Observable
public final class SharedTournamentSync {
    public private(set) var isSyncing = false
    public private(set) var lastSyncedAt: [TournamentID: Date] = [:]
    public private(set) var errors: [TournamentID: String] = [:]

    @ObservationIgnored private let store: TournamentStore
    @ObservationIgnored private let backend: SharedTournamentBackend
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var tokens: [String: Data] = [:]
    /// Guest: the newest organiser state seen in this session.
    @ObservationIgnored private var hostStates: [TournamentID: Tournament] = [:]
    @ObservationIgnored private var uploadedEventIDs: Set<EventID> = []
    @ObservationIgnored private var passRequested = false
    /// Callers waiting for the pass their request was folded into.
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Push subscriptions made in this session, by "owned by this device".
    @ObservationIgnored private var subscribedDatabases: Set<Bool> = []

    public init(store: TournamentStore, backend: SharedTournamentBackend, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.backend = backend
        self.now = now
    }

    public var hasSharedTournaments: Bool { store.tournaments.contains { $0.sharing != nil } }

    // MARK: Organiser

    /// Shares the tournament the first time and returns the invitation link.
    public func invitationURL(for id: TournamentID) async throws -> URL {
        guard let tournament = store.tournament(id) else { throw SharingError.notFound }
        if let info = tournament.sharing {
            guard info.role == .host else { throw SharingError.organiserOnly }
            if let url = try await backend.invitationURL(for: SharedZone(info)) { return url }
        }
        let shared = try await backend.share(tournament)
        try store.setSharing(SharingInfo(role: .host, zoneName: shared.zone.name, zoneOwner: shared.zone.owner, syncedRevision: tournament.revision), for: id)
        return shared.url
    }

    /// Organiser: other phones lose access; the tournament stays here as a local one.
    /// Guest: leaves the tournament and removes it from this phone.
    public func stopSharing(_ id: TournamentID) async throws {
        guard let info = store.tournament(id)?.sharing else { return }
        do {
            try await backend.removeZone(SharedZone(info))
        } catch SharingError.zoneMissing {
            // Already gone.
        }
        tokens[SharedZone(info).key] = nil
        hostStates[id] = nil
        if info.role == .guest {
            try store.delete(id)
        } else {
            try store.setSharing(nil, for: id)
        }
    }

    // MARK: Guest

    /// Adds the tournament behind an accepted invitation. Returns its ID.
    @discardableResult
    public func join(_ zone: SharedZone) async throws -> TournamentID {
        let changes = try await backend.changes(in: zone, since: nil)
        guard let host = changes.tournament else { throw SharingError.zoneMissing }
        hostStates[host.id] = host
        tokens[zone.key] = changes.token
        try store.adoptHostState(host, zoneName: zone.name, zoneOwner: zone.owner)
        return host.id
    }

    // MARK: Sync

    /// Brings every shared tournament up to date. Calls made while a pass is running are
    /// folded into one more pass and return once it has finished (a silent push must not
    /// report back before the changes it announced are in).
    public func sync() async {
        guard !isSyncing else {
            passRequested = true
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        isSyncing = true
        repeat {
            passRequested = false
            await subscribeIfNeeded()
            for id in store.tournaments.filter({ $0.sharing != nil }).map(\.id) {
                await sync(id)
            }
        } while passRequested
        isSyncing = false
        let finished = waiters
        waiters = []
        for waiter in finished { waiter.resume() }
    }

    /// Push subscriptions for the databases this device's shared tournaments live in:
    /// the organiser's own zones, the zones joined as a guest, or both. Made once per
    /// session; a failure is retried on the next pass (until then, polling while the app
    /// is on screen still brings changes in).
    private func subscribeIfNeeded() async {
        let needed = Set(store.tournaments.compactMap { $0.sharing.map { $0.role == .host } })
        for owned in [true, false] where needed.contains(owned) && !subscribedDatabases.contains(owned) {
            do {
                try await backend.subscribeToChanges(ownedByThisDevice: owned)
                subscribedDatabases.insert(owned)
            } catch {
                // Not shown: syncing itself reports connection and account problems.
            }
        }
    }

    private func sync(_ id: TournamentID) async {
        guard let info = store.tournament(id)?.sharing else { return }
        let zone = SharedZone(info)
        do {
            let changes = try await backend.changes(in: zone, since: tokens[zone.key])
            switch info.role {
            case .host: try await hostPass(id, zone: zone, changes: changes)
            case .guest: try await guestPass(id, zone: zone, changes: changes)
            }
            tokens[zone.key] = changes.token
            lastSyncedAt[id] = now()
            errors[id] = nil
        } catch SharingError.zoneMissing {
            tokens[zone.key] = nil
            hostStates[id] = nil
            // The tournament stays on this phone as a local one.
            try? store.setSharing(nil, for: id)
            errors[id] = info.role == .guest ? SharingError.zoneMissing.errorDescription : nil
        } catch {
            errors[id] = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func hostPass(_ id: TournamentID, zone: SharedZone, changes: SharedZoneChanges) async throws {
        var recorded: [EventID] = []
        if !changes.events.isEmpty {
            // The cloud returns records in no particular order. One action can create
            // several events with the same sequence (a result is "set score" then
            // "finish"); within it the match log position orders them.
            let ordered = changes.events.sorted { x, y in
                if x.deviceID != y.deviceID { return x.deviceID < y.deviceID }
                if x.deviceSequence != y.deviceSequence { return x.deviceSequence < y.deviceSequence }
                return x.baseRevision < y.baseRevision
            }
            let batch = EventBatch(deviceID: store.deviceID, events: ordered, sentAt: now())
            let result = store.applyRemote(batch)
            if let error = result.error { throw error }
            recorded = result.processed
        }
        if let tournament = store.tournament(id), tournament.revision > (tournament.sharing?.syncedRevision ?? -1) {
            try await backend.publish(tournament, in: zone)
            try store.markPublished(id, revision: tournament.revision)
        }
        // Only after the state that contains them is published.
        if !recorded.isEmpty {
            try await backend.removeEvents(recorded, from: zone)
        }
    }

    private func guestPass(_ id: TournamentID, zone: SharedZone, changes: SharedZoneChanges) async throws {
        if let host = changes.tournament {
            if let known = hostStates[id], known.revision >= host.revision {
                // Older than what this session already adopted.
            } else {
                hostStates[id] = host
                try store.adoptHostState(host, zoneName: zone.name, zoneOwner: zone.owner)
            }
        }
        guard let host = hostStates[id], let local = store.tournament(id) else { return }
        let pending = local.pendingEvents(notIn: host).filter { !uploadedEventIDs.contains($0.id) }
        guard !pending.isEmpty else { return }
        let stored = try await backend.upload(pending, to: zone)
        uploadedEventIDs.formUnion(stored)
    }
}
