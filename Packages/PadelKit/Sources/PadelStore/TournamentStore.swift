import Foundation
import Observation
import PadelCore
import PadelSync

public enum StoreError: Error, Equatable, LocalizedError, Sendable {
    case domain(TournamentError)
    case persistence(PersistenceError)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .domain(let error): error.description
        case .persistence(let error): error.description
        case .notFound: L10n.string("This tournament no longer exists.")
        }
    }
}

/// The iPhone's single source of truth for tournaments.
///
/// Every change follows the same transaction: copy → mutate with the domain engine →
/// save → publish. If the domain rejects the change or saving fails, the published state
/// is untouched, so scores and standings can never disagree with what is on disk.
@MainActor
@Observable
public final class TournamentStore {
    public private(set) var tournaments: [Tournament] = []
    public private(set) var loadIssues: [String] = []
    public private(set) var isLoaded = false

    @ObservationIgnored public let deviceID: DeviceID
    @ObservationIgnored private let repository: TournamentRepository
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let ids: IdentifierGenerating
    /// Called after every successful, saved change.
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored private var changeObservers: [() -> Void] = []

    /// Registers an additional observer (e.g. Live Activities) next to `onChange`.
    public func addChangeObserver(_ observer: @escaping () -> Void) {
        changeObservers.append(observer)
    }

    private func notifyChange() {
        onChange?()
        for observer in changeObservers { observer() }
    }

    public init(repository: TournamentRepository, deviceID: DeviceID, now: @escaping @Sendable () -> Date = { Date() }, ids: IdentifierGenerating = RandomIdentifierGenerator()) {
        self.repository = repository
        self.deviceID = deviceID
        self.now = now
        self.ids = ids
    }

    public func load() {
        let result = repository.loadAll()
        tournaments = result.tournaments.sorted { $0.createdAt > $1.createdAt }
        loadIssues = result.issues
        isLoaded = true
    }

    public func dismissLoadIssues() {
        loadIssues = []
    }

    public func context() -> EngineContext {
        EngineContext(now: now(), deviceID: deviceID, ids: ids)
    }

    // MARK: Queries

    public func tournament(_ id: TournamentID) -> Tournament? {
        tournaments.first { $0.id == id }
    }

    /// Active tournaments, most recently changed first.
    public var activeTournaments: [Tournament] {
        tournaments.filter { $0.status == .active }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The tournament to resume from Home.
    public var resumableTournament: Tournament? { activeTournaments.first }

    public var recentTournaments: [Tournament] {
        tournaments.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: Commands

    @discardableResult
    public func create(_ draft: TournamentDraft) throws(StoreError) -> Tournament {
        let tournament: Tournament
        do {
            tournament = try Tournament.create(from: draft, context: context())
        } catch {
            throw .domain(error)
        }
        do {
            try repository.save(tournament)
        } catch {
            throw .persistence(error)
        }
        tournaments.insert(tournament, at: 0)
        notifyChange()
        return tournament
    }

    /// Runs a domain operation as a transaction. Returns the operation's result.
    @discardableResult
    public func perform<Result>(_ id: TournamentID, _ operation: (inout Tournament, EngineContext) throws(TournamentError) -> Result) throws(StoreError) -> Result {
        guard let index = tournaments.firstIndex(where: { $0.id == id }) else { throw .notFound }
        var copy = tournaments[index]
        let result: Result
        do {
            result = try operation(&copy, context())
        } catch {
            throw .domain(error)
        }
        guard copy != tournaments[index] else { return result }
        do {
            try repository.save(copy)
        } catch {
            throw .persistence(error)
        }
        tournaments[index] = copy
        notifyChange()
        return result
    }

    public func delete(_ id: TournamentID) throws(StoreError) {
        do {
            try repository.delete(id)
        } catch {
            throw .persistence(error)
        }
        tournaments.removeAll { $0.id == id }
        notifyChange()
    }

    // MARK: Scoring shortcuts

    public func recordPoint(_ side: TeamSide, match: MatchID, in tournament: TournamentID) throws(StoreError) {
        try perform(tournament) { (t, c) throws(TournamentError) in _ = try t.recordPoint(for: side, in: match, context: c) }
    }

    public func undo(match: MatchID, in tournament: TournamentID) throws(StoreError) {
        try perform(tournament) { (t, c) throws(TournamentError) in _ = try t.undoLastScoreChange(in: match, context: c) }
    }

    public func finish(match: MatchID, in tournament: TournamentID) throws(StoreError) {
        try perform(tournament) { (t, c) throws(TournamentError) in try t.finishMatch(match, context: c) }
    }

    public func enterResult(_ score: Score, match: MatchID, in tournament: TournamentID) throws(StoreError) {
        try perform(tournament) { (t, c) throws(TournamentError) in try t.enterResult(score, for: match, context: c) }
    }

    public func enterSetsResult(_ sets: [Score], match: MatchID, in tournament: TournamentID) throws(StoreError) {
        try perform(tournament) { (t, c) throws(TournamentError) in try t.enterSetsResult(sets, for: match, context: c) }
    }

    public func reopen(match: MatchID, in tournament: TournamentID) throws(StoreError) {
        try perform(tournament) { (t, c) throws(TournamentError) in try t.reopenMatch(match, context: c) }
    }

    // MARK: Sharing

    public func setSharing(_ info: SharingInfo?, for id: TournamentID) throws(StoreError) {
        try perform(id) { (t, _) throws(TournamentError) in t.setSharing(info) }
    }

    /// Host: records that `revision` is what the other phones now see.
    public func markPublished(_ id: TournamentID, revision: Int) throws(StoreError) {
        try perform(id) { (t, _) throws(TournamentError) in t.markPublished(revision: revision) }
    }

    /// Guest: stores the organiser's latest state, keeping this phone's unconfirmed
    /// events on top. A tournament seen for the first time is added.
    @discardableResult
    public func adoptHostState(_ host: Tournament, zoneName: String, zoneOwner: String) throws(StoreError) -> Tournament.RebaseOutcome {
        guard let existing = tournament(host.id) else {
            let copy = Tournament.guestCopy(of: host, zoneName: zoneName, zoneOwner: zoneOwner)
            do {
                try repository.save(copy)
            } catch {
                throw .persistence(error)
            }
            tournaments.insert(copy, at: 0)
            notifyChange()
            return .adopted(replayed: 0)
        }
        // The organiser opening their own invitation, or a local tournament with the
        // same identity: never overwrite it.
        guard existing.isGuest else { return .notGuest }
        return try perform(host.id) { (t, c) throws(TournamentError) in t.rebase(onto: host, now: c.now) }
    }

    // MARK: Remote events

    public struct RemoteResult: Sendable, Equatable {
        /// True when anything was saved.
        public var changed: Bool
        /// Event IDs that were durably processed (applied, duplicate or recorded conflict).
        public var processed: [EventID]
        /// Events whose tournament no longer exists.
        public var unroutable: [ScoreConflict]
        /// Set when saving failed; nothing from the batch is acknowledged then.
        public var error: StoreError?
    }

    /// Applies a batch received from the watch. Each tournament is saved before any of
    /// its events count as processed.
    public func applyRemote(_ batch: EventBatch) -> RemoteResult {
        var result = RemoteResult(changed: false, processed: [], unroutable: [], error: nil)
        let grouped = Dictionary(grouping: batch.events, by: \.tournamentID)
        // (On a guest's phone these are its watch's events: they are applied to the
        // guest copy here and forwarded to the organiser by the shared sync.)
        for (tournamentID, events) in grouped.sorted(by: { $0.key < $1.key }) {
            guard tournaments.contains(where: { $0.id == tournamentID }) else {
                let at = now()
                result.unroutable += events.map { ScoreConflict(event: $0, reason: .unknownTournament, recordedAt: at) }
                result.processed += events.map(\.id)
                continue
            }
            do {
                let report = try perform(tournamentID) { (t, c) throws(TournamentError) in t.applyRemoteEvents(events, context: c) }
                result.processed += report.processedIDs
                if !report.applied.isEmpty || !report.conflicts.isEmpty { result.changed = true }
            } catch {
                result.error = error
            }
        }
        return result
    }
}
