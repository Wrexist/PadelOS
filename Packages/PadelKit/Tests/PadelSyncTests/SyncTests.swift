import Foundation
import Testing
@testable import PadelCore
@testable import PadelSync
@testable import PadelStore

/// A paired iPhone + watch wired through in-memory transports.
@MainActor
final class Harness {
    let phoneTransport: InMemorySyncTransport
    let watchTransport: InMemorySyncTransport
    let repository: InMemoryTournamentRepository
    let store: TournamentStore
    let settings: SettingsStore
    let coordinator: PhoneSyncCoordinator
    var watch: WatchStore
    let watchFile: JSONFileStore<WatchSyncState>
    let directory: URL

    init(watchReachable: Bool = true) {
        (phoneTransport, watchTransport) = InMemorySyncTransport.pair()
        watchTransport.isReachable = watchReachable
        phoneTransport.isReachable = watchReachable
        repository = InMemoryTournamentRepository()
        store = TournamentStore(repository: repository, deviceID: DeviceID(), now: { Date(timeIntervalSince1970: 1_800_000_000) })
        store.load()
        settings = SettingsStore(file: nil)
        coordinator = PhoneSyncCoordinator(store: store, settings: settings, transport: phoneTransport)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("padel-sync-\(UUID().uuidString)")
        watchFile = JSONFileStore(url: directory.appendingPathComponent("WatchState.json"), schemaVersion: 1)
        watch = WatchStore(file: watchFile, transport: watchTransport)
        coordinator.start()
        watch.start()
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func setReachable(_ reachable: Bool) {
        phoneTransport.isReachable = reachable
        watchTransport.isReachable = reachable
    }

    @discardableResult
    func createTournament(format: TournamentFormat = .americano, players: Int = 8, points: Int = 24, rounds: Int = 3) throws -> Tournament {
        let names = ["Alex", "Lisa", "Johan", "Maja", "Erik", "Daniel", "Sofia", "Fredrik", "Anna", "Oscar"]
        let draft = TournamentDraft(
            name: "Friday Padel",
            configuration: TournamentConfiguration(format: format, courtCount: 2, roundCount: rounds, scoring: .totalPoints(points)),
            players: (0..<players).map { Player(name: names[$0]) }
        )
        let tournament = try store.create(draft)
        phoneTransport.deliverLatestState()
        return tournament
    }

    func phoneMatch(_ tournament: TournamentID, _ match: MatchID) -> Match? {
        store.tournament(tournament)?.match(match)
    }

    func watchMatch(_ tournament: TournamentID, _ match: MatchID) -> Match? {
        watch.state.tournament(tournament)?.match(match)
    }

    /// Simulates the watch app being terminated and relaunched.
    func relaunchWatch() {
        watch = WatchStore(file: watchFile, transport: watchTransport)
        watch.start()
    }
}

@Suite("iPhone ⇄ Watch synchronisation")
@MainActor
struct SyncTests {
    @Test("iPhone to watch: the snapshot delivers the tournament")
    func phoneToWatch() throws {
        let h = Harness()
        #expect(h.watch.syncStatus == .waitingForPhone)
        let t = try h.createTournament()
        #expect(h.watch.tournaments.map(\.id) == [t.id])
        #expect(h.watch.syncStatus == .upToDate)
    }

    @Test("Watch to iPhone while reachable: applied and acknowledged in one round trip")
    func watchToPhoneReachable() throws {
        let h = Harness()
        let t = try h.createTournament()
        let match = t.rounds[0].matches[0].id
        #expect(h.watch.recordPoint(.a, match: match, tournament: t.id))
        #expect(h.watch.recordPoint(.a, match: match, tournament: t.id))
        #expect(h.watch.recordPoint(.b, match: match, tournament: t.id))
        #expect(h.phoneMatch(t.id, match)?.score == Score(a: 2, b: 1))
        #expect(h.watch.state.pending.isEmpty)
        #expect(h.watchMatch(t.id, match)?.score == Score(a: 2, b: 1))
        #expect(h.watch.undo(match: match, tournament: t.id))
        #expect(h.phoneMatch(t.id, match)?.score == Score(a: 2, b: 0))
    }

    @Test("Offline scoring is kept on the watch and replayed on reconnection")
    func offlineThenReconnect() throws {
        let h = Harness()
        let t = try h.createTournament()
        let match = t.rounds[0].matches[0].id
        h.setReachable(false)
        for _ in 0..<5 { #expect(h.watch.recordPoint(.a, match: match, tournament: t.id)) }
        #expect(h.watch.undo(match: match, tournament: t.id))
        #expect(h.watchMatch(t.id, match)?.score == Score(a: 4, b: 0))
        #expect(h.phoneMatch(t.id, match)?.score == .zero)
        #expect(h.watch.syncStatus == .pending(count: 6, reachable: false))
        // Batches are cumulative and replace each other: only one transfer is queued.
        #expect(h.watchTransport.durableQueue.count == 1)

        h.setReachable(true)
        h.watchTransport.deliverAll()           // watch → phone (queued transfer)
        #expect(h.phoneMatch(t.id, match)?.score == Score(a: 4, b: 0))
        h.phoneTransport.deliverLatestState()   // phone → watch (acknowledging snapshot)
        #expect(h.watch.state.pending.isEmpty)
        #expect(h.watch.syncStatus == .upToDate)
    }

    @Test("Duplicate delivery never adds points twice")
    func duplicateDelivery() throws {
        let h = Harness(watchReachable: false)
        let t = try h.createTournament()
        let match = t.rounds[0].matches[0].id
        for _ in 0..<3 { h.watch.recordPoint(.b, match: match, tournament: t.id) }
        h.watchTransport.deliverAll(duplicate: true)
        // And the same batch arrives once more via an immediate message.
        let batch = try #require(h.watch.state.outgoingBatch(now: Date()))
        h.coordinator.handle(.eventBatch(batch), reply: nil)
        #expect(h.phoneMatch(t.id, match)?.score == Score(a: 0, b: 3))
    }

    @Test("Out-of-order batches are applied in recording order")
    func outOfOrder() throws {
        let h = Harness(watchReachable: false)
        let t = try h.createTournament(points: 4)
        let match = t.rounds[0].matches[0].id
        h.watch.recordPoint(.a, match: match, tournament: t.id)
        h.watch.recordPoint(.a, match: match, tournament: t.id)
        let first = try #require(h.watch.state.outgoingBatch(now: Date()))
        h.watch.undo(match: match, tournament: t.id)
        h.watch.recordPoint(.b, match: match, tournament: t.id)
        h.watch.recordPoint(.b, match: match, tournament: t.id)
        h.watch.recordPoint(.b, match: match, tournament: t.id)
        h.watch.finish(match: match, tournament: t.id)
        let second = try #require(h.watch.state.outgoingBatch(now: Date()))
        // The newer, cumulative batch arrives first; the older one arrives late.
        h.coordinator.handle(.eventBatch(second), reply: nil)
        h.coordinator.handle(.eventBatch(first), reply: nil)
        let phone = try #require(h.phoneMatch(t.id, match))
        #expect(phone.score == Score(a: 1, b: 3))
        #expect(phone.isCompleted)
        #expect(phone.conflicts.isEmpty)
    }

    @Test("Stale snapshots never overwrite newer results")
    func staleSnapshot() throws {
        let h = Harness()
        let t = try h.createTournament()
        let match = t.rounds[0].matches[0].id
        let old = try #require(h.watch.state.snapshot)
        h.watch.recordPoint(.a, match: match, tournament: t.id)
        let newer = try #require(h.watch.state.snapshot)
        #expect(newer.sequence > old.sequence)
        h.watch.receive(.snapshot(old))
        #expect(h.watch.state.snapshot == newer)
        #expect(h.watchMatch(t.id, match)?.score == Score(a: 1, b: 0))
    }

    @Test("A reinstalled iPhone app (new instance) is accepted despite a lower sequence")
    func newPhoneInstance() throws {
        let h = Harness()
        _ = try h.createTournament()
        let current = try #require(h.watch.state.snapshot)
        let fresh = WatchSnapshot(phoneInstanceID: UUID(), sequence: 1, generatedAt: Date(), tournaments: [], acknowledgedEventIDs: [])
        h.watch.receive(.snapshot(fresh))
        #expect(h.watch.state.snapshot != current)
        #expect(h.watch.tournaments.isEmpty)
    }

    @Test("Pending events survive a watch app restart and are delivered afterwards")
    func restartWithPending() throws {
        let h = Harness(watchReachable: false)
        let t = try h.createTournament()
        let match = t.rounds[0].matches[0].id
        for _ in 0..<4 { h.watch.recordPoint(.a, match: match, tournament: t.id) }
        h.watchTransport.dropQueued()           // the system lost the queued transfer
        h.relaunchWatch()
        #expect(h.watch.state.pending.count == 4)
        #expect(h.watchMatch(t.id, match)?.score == Score(a: 4, b: 0))
        h.setReachable(true)
        h.watch.flush()
        #expect(h.phoneMatch(t.id, match)?.score == Score(a: 4, b: 0))
        #expect(h.watch.state.pending.isEmpty)
    }

    @Test("Points recorded on the watch after the iPhone finished the match become visible conflicts")
    func conflictingEdits() throws {
        let h = Harness(watchReachable: false)
        let t = try h.createTournament(points: 4)
        let match = t.rounds[0].matches[0].id
        h.watch.recordPoint(.a, match: match, tournament: t.id)
        h.watch.recordPoint(.a, match: match, tournament: t.id)
        try h.store.enterResult(Score(a: 1, b: 3), match: match, in: t.id)  // organiser enters result on iPhone
        h.setReachable(true)
        h.watchTransport.deliverAll()
        h.phoneTransport.deliverLatestState()
        let phone = try #require(h.phoneMatch(t.id, match))
        #expect(phone.score == Score(a: 1, b: 3), "the phone's finished result stands")
        #expect(phone.openConflicts.count == 2, "watch points are kept for review, not discarded")
        #expect(h.store.tournament(t.id)?.openConflictCount == 2)
        // The watch's outbox is acknowledged and its view now shows the authoritative result.
        #expect(h.watch.state.pending.isEmpty)
        #expect(h.watchMatch(t.id, match)?.score == Score(a: 1, b: 3))
    }

    @Test("Events are not acknowledged if the iPhone could not save them")
    func saveFailureIsNotAcknowledged() throws {
        let h = Harness()
        let t = try h.createTournament()
        let match = t.rounds[0].matches[0].id
        h.repository.failAllSaves = true
        h.watch.recordPoint(.a, match: match, tournament: t.id)
        #expect(h.phoneMatch(t.id, match)?.score == .zero)
        #expect(h.watch.state.pending.count == 1, "kept on the watch")
        #expect(h.coordinator.lastError != nil)
        h.repository.failAllSaves = false
        h.watch.flush()
        #expect(h.phoneMatch(t.id, match)?.score == Score(a: 1, b: 0))
        #expect(h.watch.state.pending.isEmpty)
    }

    @Test("Finishing the last Mexicano match on the watch makes the iPhone create the next round")
    func mexicanoNextRoundFromWatch() throws {
        let h = Harness()
        let t = try h.createTournament(format: .mexicano, points: 4, rounds: 3)
        for match in t.rounds[0].matches {
            for _ in 0..<3 { h.watch.recordPoint(.a, match: match.id, tournament: t.id) }
            h.watch.recordPoint(.b, match: match.id, tournament: t.id)
            #expect(h.watch.finish(match: match.id, tournament: t.id))
        }
        #expect(h.store.tournament(t.id)?.rounds.count == 2)
        #expect(h.watch.state.tournament(t.id)?.rounds.count == 2)
    }

    @Test("Events for a tournament deleted on the iPhone are kept and acknowledged")
    func unroutable() throws {
        let h = Harness(watchReachable: false)
        let t = try h.createTournament()
        let match = t.rounds[0].matches[0].id
        h.watch.recordPoint(.a, match: match, tournament: t.id)
        try h.store.delete(t.id)
        h.setReachable(true)
        h.watchTransport.deliverAll()
        h.phoneTransport.deliverLatestState()
        #expect(h.settings.settings.unroutableEvents.count == 1)
        #expect(h.watch.state.pending.isEmpty)
        #expect(h.watch.tournaments.isEmpty)
    }

    @Test("Watch refuses invalid actions without recording anything")
    func watchValidation() throws {
        let h = Harness()
        let t = try h.createTournament(points: 4)
        let match = t.rounds[0].matches[0].id
        #expect(!h.watch.undo(match: match, tournament: t.id))
        #expect(!h.watch.finish(match: match, tournament: t.id))
        for _ in 0..<4 { h.watch.recordPoint(.a, match: match, tournament: t.id) }
        #expect(!h.watch.recordPoint(.a, match: match, tournament: t.id))
        #expect(h.watch.lastError != nil)
        #expect(h.phoneMatch(t.id, match)?.score == Score(a: 4, b: 0))
    }

    @Test("Snapshots stay small for a large tournament")
    func snapshotSize() throws {
        let players = (0..<24).map { Player(name: "Player \($0)") }
        let config = TournamentConfiguration(format: .americano, courtCount: 6, roundCount: 10, scoring: .totalPoints(32))
        var t = try Tournament.create(from: TournamentDraft(name: "Big", configuration: config, players: players), context: EngineContext(now: Date(), deviceID: DeviceID()))
        let context = EngineContext(now: Date(), deviceID: DeviceID())
        for round in t.rounds.prefix(6) {
            for match in round.matches {
                for i in 0..<32 { try t.recordPoint(for: i % 3 == 0 ? .b : .a, in: match.id, context: context) }
                try t.finishMatch(match.id, context: context)
            }
        }
        let snapshot = WatchSnapshot.make(from: [t], phoneInstanceID: UUID(), sequence: 1, now: Date())
        let size = try SyncCodec.encodedSize(.snapshot(snapshot))
        #expect(size < 64_000, "snapshot is \(size) bytes")
        #expect(snapshot.tournaments.count == 1)
    }

    @Test("Codec round trip and version handling")
    func codec() throws {
        let batch = EventBatch(deviceID: DeviceID(), events: [], sentAt: Date(timeIntervalSince1970: 1_800_000_000))
        let encoded = try SyncCodec.encode(.eventBatch(batch))
        #expect(try SyncCodec.decode(encoded) == .eventBatch(batch))
        var future = encoded
        future[SyncCodec.versionKey] = 99
        #expect(throws: SyncCodec.DecodeError.unsupportedVersion(99)) { try SyncCodec.decode(future) }
        #expect(throws: SyncCodec.DecodeError.notAPadelMessage) { try SyncCodec.decode(["x": 1]) }
        #expect(throws: SyncCodec.DecodeError.corrupt) { try SyncCodec.decode([SyncCodec.versionKey: 1, SyncCodec.payloadKey: Data("{".utf8)]) }
    }

    @Test("Randomised delivery: drops, duplicates and reordering converge (seed 4242)")
    func randomisedConvergence() throws {
        let h = Harness(watchReachable: false)
        let t = try h.createTournament(points: 40)
        let match = t.rounds[0].matches[0].id
        var random = SeededGenerator(seed: 4242)
        var expected = Score.zero
        for _ in 0..<60 {
            let action = random.nextInt(10)
            switch action {
            case 0...5:
                let side: TeamSide = random.nextInt(2) == 0 ? .a : .b
                if h.watch.recordPoint(side, match: match, tournament: t.id) { expected[side] += 1 }
            case 6:
                let before = h.watchMatch(t.id, match)?.score
                if h.watch.undo(match: match, tournament: t.id), let before, let after = h.watchMatch(t.id, match)?.score {
                    expected = after
                    #expect(after.total == before.total - 1)
                }
            case 7:
                h.setReachable(random.nextInt(2) == 0)
            case 8:
                h.watchTransport.deliverAll(duplicate: random.nextInt(2) == 0, reversed: random.nextInt(2) == 0)
                h.phoneTransport.deliverLatestState()
            default:
                h.watchTransport.dropQueued()
            }
            #expect(h.watchMatch(t.id, match)?.score == expected)
        }
        h.setReachable(true)
        h.watch.flush()
        #expect(h.phoneMatch(t.id, match)?.score == expected)
        #expect(h.watch.state.pending.isEmpty)
        #expect(h.phoneMatch(t.id, match)?.conflicts.isEmpty == true)
    }
}
