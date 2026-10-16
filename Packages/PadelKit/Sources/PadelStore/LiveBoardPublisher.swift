import Foundation
import Observation
import PadelCore

/// Where spectator boards are published. CloudKit's public database in the app, in
/// memory in tests.
public protocol LiveBoardBackend: Sendable {
    /// Creates or replaces the public record named `token`.
    func publish(token: String, payload: String, updatedAt: Date) async throws
    /// Deletes the record named `token`. Succeeds when it is already gone.
    func remove(token: String) async throws
}

public enum LiveBoardToken {
    /// A fresh random token (system random generator).
    public static func random() -> String {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    public static func random<Generator: RandomNumberGenerator>(using generator: inout Generator) -> String {
        String((0..<LiveBoard.tokenLength).map { _ in LiveBoard.tokenAlphabet.randomElement(using: &generator)! })
    }
}

/// Keeps the public spectator boards of the organiser's tournaments up to date.
///
/// - `start` gives a tournament a random token and publishes its board right away.
/// - After every change the boards are republished, at most once per `delay` (a burst
///   of points becomes one upload), and only when something visible changed.
/// - `stop` deletes the public record before the token is forgotten; if that fails the
///   board stays on and the error is thrown, so a record is never left behind silently.
/// - Deleting a tournament deletes its record (retried on later passes when offline).
///
/// Guest copies never publish: the board belongs to the organiser's phone.
@MainActor
@Observable
public final class LiveBoardPublisher {
    /// Last publishing problem per tournament (cleared by the next success).
    public private(set) var errors: [TournamentID: String] = [:]
    public private(set) var lastPublishedAt: [TournamentID: Date] = [:]

    @ObservationIgnored private let store: TournamentStore
    @ObservationIgnored private let backend: LiveBoardBackend
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let makeToken: @Sendable () -> String
    /// Boards seen on this phone, so a deleted tournament's record can be removed.
    @ObservationIgnored private var known: [TournamentID: String] = [:]
    /// What each record holds (time left out), to skip uploads that change nothing.
    @ObservationIgnored private var published: [String: LiveBoardSnapshot] = [:]
    /// Records to delete whose tournament is gone.
    @ObservationIgnored private var pendingRemovals: Set<String> = []
    /// Records `stop` is deleting; passes leave them alone.
    @ObservationIgnored private var stopping: Set<String> = []
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var passRequested = false

    public init(
        store: TournamentStore,
        backend: LiveBoardBackend,
        delay: Duration = .seconds(2),
        now: @escaping @Sendable () -> Date = { Date() },
        makeToken: @escaping @Sendable () -> String = { LiveBoardToken.random() }
    ) {
        self.store = store
        self.backend = backend
        self.delay = delay
        self.now = now
        self.makeToken = makeToken
    }

    /// True when there is anything to publish or remove.
    public var hasBoards: Bool {
        !known.isEmpty || !pendingRemovals.isEmpty || store.tournaments.contains { $0.liveBoardToken != nil && !$0.isGuest }
    }

    // MARK: Organiser

    /// Shares the tournament's board (creating its token the first time), publishes it
    /// and returns the spectator link. A failed upload is kept in `errors` and retried
    /// with the next change.
    @discardableResult
    public func start(_ id: TournamentID) async throws -> URL {
        guard let tournament = store.tournament(id) else { throw StoreError.notFound }
        let token: String
        if let existing = tournament.liveBoardToken {
            token = existing
        } else {
            token = makeToken()
            try store.setLiveBoardToken(token, for: id)
        }
        await sync()
        return LiveBoard.url(token: token)
    }

    /// Takes the board off the web: the record is deleted first, then the token is
    /// forgotten. Throws (and keeps the board on) when the record cannot be deleted.
    public func stop(_ id: TournamentID) async throws {
        // Let an upload in flight finish so it cannot recreate the record afterwards.
        while let running { await running.value }
        guard let token = store.tournament(id)?.liveBoardToken else { return }
        stopping.insert(token)
        defer { stopping.remove(token) }
        try await backend.remove(token: token)
        published[token] = nil
        pendingRemovals.remove(token)
        known[id] = nil
        errors[id] = nil
        lastPublishedAt[id] = nil
        try store.setLiveBoardToken(nil, for: id)
    }

    // MARK: Publishing

    /// Call once the store is loaded: remembers the boards already on (so deleting one of
    /// those tournaments removes its record) and republishes them.
    public func resume() async {
        for tournament in store.tournaments where !tournament.isGuest {
            if let token = tournament.liveBoardToken { known[tournament.id] = token }
        }
        guard hasBoards else { return }
        await sync()
    }

    /// Call after every store change: publishes once `delay` has passed.
    public func storeDidChange() {
        guard hasBoards, scheduled == nil else { return }
        let delay = delay
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            self.scheduled = nil
            await self.sync()
        }
    }

    /// Publishes every board that changed and removes deleted ones now. Calls made while
    /// a pass is running are folded into one more pass.
    public func sync() async {
        if let running {
            passRequested = true
            await running.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.passRequested = false
                await self.pass()
            } while self.passRequested
            self.running = nil
        }
        running = task
        await task.value
    }

    /// Waits until no publish is scheduled or running (e.g. to end a background task).
    public func waitUntilIdle() async {
        while true {
            if let scheduled {
                await scheduled.value
            } else if let running {
                await running.value
            } else {
                return
            }
        }
    }

    private func pass() async {
        let boards = store.tournaments.compactMap { tournament -> (token: String, tournament: Tournament)? in
            guard !tournament.isGuest, let token = tournament.liveBoardToken else { return nil }
            return (token, tournament)
        }
        let current = Dictionary(boards.map { ($0.tournament.id, $0.token) }, uniquingKeysWith: { first, _ in first })
        for (id, token) in known where current[id] != token {
            known[id] = nil
            pendingRemovals.insert(token)
            errors[id] = nil
            lastPublishedAt[id] = nil
        }
        for token in pendingRemovals.sorted() where !stopping.contains(token) {
            do {
                try await backend.remove(token: token)
                pendingRemovals.remove(token)
                published[token] = nil
            } catch {
                // Kept; tried again on the next pass.
            }
        }
        for (token, tournament) in boards where !stopping.contains(token) && !pendingRemovals.contains(token) {
            let id = tournament.id
            known[id] = token
            let board = LiveBoardSnapshot(tournament: tournament, updatedAt: now())
            let content = board.at(.distantPast)
            guard published[token] != content else { continue }
            do {
                try await backend.publish(token: token, payload: try board.json(), updatedAt: board.updatedAt)
                published[token] = content
                lastPublishedAt[id] = board.updatedAt
                errors[id] = nil
            } catch {
                errors[id] = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }
}
