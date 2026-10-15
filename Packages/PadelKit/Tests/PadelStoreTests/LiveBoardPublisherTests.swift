import Foundation
import Testing
@testable import PadelCore
@testable import PadelSync
@testable import PadelStore

/// CloudKit's public database, in memory.
final class InMemoryLiveBoardBackend: LiveBoardBackend, @unchecked Sendable {
    struct Record: Equatable {
        var payload: String
        var updatedAt: Date
    }

    private let lock = NSLock()
    private var storage: [String: Record] = [:]
    private var publishes = 0
    private var offline = false

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    var records: [String: Record] { locked { storage } }
    var publishCount: Int { locked { publishes } }
    var isOffline: Bool {
        get { locked { offline } }
        set { locked { offline = newValue } }
    }

    func board(_ token: String) throws -> LiveBoardSnapshot? {
        try records[token].map { try LiveBoardSnapshot.decode($0.payload) }
    }

    func publish(token: String, payload: String, updatedAt: Date) async throws {
        try locked {
            if offline { throw SharingError.service("offline") }
            storage[token] = Record(payload: payload, updatedAt: updatedAt)
            publishes += 1
        }
    }

    func remove(token: String) async throws {
        try locked {
            if offline { throw SharingError.service("offline") }
            storage[token] = nil
        }
    }
}

@MainActor
private struct Organiser {
    let store: TournamentStore
    let cloud: InMemoryLiveBoardBackend
    let boards: LiveBoardPublisher

    /// A phone whose tournaments are saved in `repository`; publishes to `cloud`.
    init(repository: TournamentRepository = InMemoryTournamentRepository(), cloud: InMemoryLiveBoardBackend = InMemoryLiveBoardBackend(), token: String = "AbCdEfGhIjKlMnOpQrStUv01") {
        let store = TournamentStore(repository: repository, deviceID: DeviceID())
        store.load()
        let boards = LiveBoardPublisher(store: store, backend: cloud, delay: .milliseconds(30), makeToken: { token })
        // As the app does: every saved change schedules a publish.
        store.addChangeObserver { boards.storeDidChange() }
        self.store = store
        self.cloud = cloud
        self.boards = boards
    }

    func createTournament() throws -> Tournament {
        let names = ["Alex", "Lisa", "Johan", "Maja", "Erik", "Daniel", "Sofia", "Fredrik"]
        let configuration = TournamentConfiguration(format: .americano, courtCount: 2, roundCount: 3, scoring: .totalPoints(16))
        return try store.create(TournamentDraft(name: "Friday Padel", configuration: configuration, players: names.map { Player(name: $0) }))
    }
}

@Suite("Spectator board publishing")
@MainActor
struct LiveBoardPublisherTests {
    let token = "AbCdEfGhIjKlMnOpQrStUv01"

    @Test("Sharing creates a token, publishes at once and returns the link")
    func start() async throws {
        let phone = Organiser()
        let tournament = try phone.createTournament()
        let url = try await phone.boards.start(tournament.id)
        #expect(url.absoluteString == "https://wrexist.github.io/PadelOS/live/#\(token)")
        #expect(phone.store.tournament(tournament.id)?.liveBoardToken == token)
        #expect(phone.cloud.publishCount == 1)
        let board = try #require(try phone.cloud.board(token))
        #expect(board.name == "Friday Padel")
        #expect(board.standings.count == 8)
        #expect(board.courts.count == 2)
        #expect(phone.boards.errors[tournament.id] == nil)
        #expect(phone.boards.lastPublishedAt[tournament.id] != nil)

        // Sharing again keeps the same link.
        #expect(try await phone.boards.start(tournament.id) == url)
        await phone.boards.waitUntilIdle()
        #expect(phone.cloud.publishCount == 1, "nothing visible changed")
    }

    @Test("A burst of points becomes one upload after the delay")
    func debounced() async throws {
        let phone = Organiser()
        let tournament = try phone.createTournament()
        try await phone.boards.start(tournament.id)
        let match = try #require(tournament.rounds.first?.matches.first).id
        try phone.store.recordPoint(.a, match: match, in: tournament.id)
        try phone.store.recordPoint(.a, match: match, in: tournament.id)
        try phone.store.recordPoint(.b, match: match, in: tournament.id)
        #expect(phone.cloud.publishCount == 1, "not before the delay")
        await phone.boards.waitUntilIdle()
        #expect(phone.cloud.publishCount == 2)
        let court = try #require(try phone.cloud.board(token)?.courts.first)
        #expect(court.state == .live)
        #expect(court.scoreA == "2" && court.scoreB == "1")
    }

    @Test("Changes to other tournaments or no visible change do not upload")
    func unchangedNotUploaded() async throws {
        let phone = Organiser()
        let shared = try phone.createTournament()
        try await phone.boards.start(shared.id)
        let other = try phone.createTournament()
        let match = try #require(other.rounds.first?.matches.first).id
        try phone.store.recordPoint(.a, match: match, in: other.id)
        await phone.boards.waitUntilIdle()
        await phone.boards.sync()
        #expect(phone.cloud.publishCount == 1)
        #expect(phone.cloud.records.count == 1)
    }

    @Test("Uploads that fail are reported and retried with the next pass")
    func offlineRetry() async throws {
        let phone = Organiser()
        let tournament = try phone.createTournament()
        phone.cloud.isOffline = true
        let url = try await phone.boards.start(tournament.id)
        #expect(url.absoluteString.hasSuffix(token), "the link is ready even before the first upload")
        #expect(phone.boards.errors[tournament.id] != nil)
        #expect(phone.cloud.records.isEmpty)

        phone.cloud.isOffline = false
        await phone.boards.sync()
        #expect(phone.boards.errors[tournament.id] == nil)
        #expect(phone.cloud.records[token] != nil)
    }

    @Test("Stopping deletes the public record, then forgets the token")
    func stop() async throws {
        let phone = Organiser()
        let tournament = try phone.createTournament()
        try await phone.boards.start(tournament.id)
        try await phone.boards.stop(tournament.id)
        #expect(phone.cloud.records.isEmpty)
        #expect(phone.store.tournament(tournament.id)?.liveBoardToken == nil)

        // Later changes publish nothing.
        let match = try #require(tournament.rounds.first?.matches.first).id
        try phone.store.recordPoint(.a, match: match, in: tournament.id)
        await phone.boards.waitUntilIdle()
        #expect(phone.cloud.records.isEmpty)
        #expect(!phone.boards.hasBoards)
    }

    @Test("Stopping while offline keeps the board on and reports the error")
    func stopOffline() async throws {
        let phone = Organiser()
        let tournament = try phone.createTournament()
        try await phone.boards.start(tournament.id)
        phone.cloud.isOffline = true
        await #expect(throws: SharingError.self) { try await phone.boards.stop(tournament.id) }
        #expect(phone.store.tournament(tournament.id)?.liveBoardToken == token)
        phone.cloud.isOffline = false
        try await phone.boards.stop(tournament.id)
        #expect(phone.cloud.records.isEmpty)
    }

    @Test("Stopping waits for an upload in flight, so the record cannot come back")
    func stopDuringPublish() async throws {
        let phone = Organiser()
        let tournament = try phone.createTournament()
        try await phone.boards.start(tournament.id)
        let match = try #require(tournament.rounds.first?.matches.first).id
        try phone.store.recordPoint(.a, match: match, in: tournament.id)
        let boards = phone.boards
        async let publishing: Void = boards.sync()
        try await phone.boards.stop(tournament.id)
        await publishing
        await phone.boards.waitUntilIdle()
        #expect(phone.cloud.records.isEmpty)
    }

    @Test("Deleting the tournament deletes its record, retrying when offline")
    func deleteTournament() async throws {
        let phone = Organiser()
        let tournament = try phone.createTournament()
        try await phone.boards.start(tournament.id)
        phone.cloud.isOffline = true
        try phone.store.delete(tournament.id)
        await phone.boards.waitUntilIdle()
        #expect(phone.cloud.records[token] != nil, "still there while offline")
        #expect(phone.boards.hasBoards)

        phone.cloud.isOffline = false
        await phone.boards.sync()
        #expect(phone.cloud.records.isEmpty)
        #expect(!phone.boards.hasBoards)
    }

    @Test("After a relaunch boards are republished and a deletion still removes the record")
    func relaunch() async throws {
        let repository = InMemoryTournamentRepository()
        let first = Organiser(repository: repository)
        let tournament = try first.createTournament()
        try await first.boards.start(tournament.id)

        // Same saved tournaments, new store and publisher (as after the app restarts).
        let relaunched = Organiser(repository: repository, cloud: first.cloud, token: "unused")
        await relaunched.boards.resume()
        #expect(first.cloud.publishCount == 2)
        try relaunched.store.delete(tournament.id)
        await relaunched.boards.waitUntilIdle()
        #expect(first.cloud.records.isEmpty)
    }

    @Test("Guest copies never publish a board")
    func guests() async throws {
        let phone = Organiser()
        let tournament = try phone.createTournament()
        var host = try #require(phone.store.tournament(tournament.id))
        host.name = "Hosted elsewhere"
        let guestPhone = Organiser()
        try guestPhone.store.adoptHostState(host, zoneName: "zone", zoneOwner: "owner")
        await #expect(throws: StoreError.self) { try await guestPhone.boards.start(tournament.id) }
        #expect(!guestPhone.boards.hasBoards)
        await guestPhone.boards.sync()
        #expect(guestPhone.cloud.records.isEmpty)
    }

    @Test("Tokens are 24 base62 characters and differ every time")
    func randomTokens() {
        let tokens = (0..<50).map { _ in LiveBoardToken.random() }
        #expect(Set(tokens).count == 50)
        #expect(tokens.allSatisfy { $0.count == 24 && LiveBoard.isValidToken($0) })
    }
}
