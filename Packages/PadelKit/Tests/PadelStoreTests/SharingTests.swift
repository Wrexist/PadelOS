import Foundation
import Testing
@testable import PadelCore
@testable import PadelSync
@testable import PadelStore

/// A shared cloud for several simulated phones: one zone per shared tournament holding
/// the organiser's state and the events guests uploaded. Tokens are change counters.
final class SimulatedCloud: @unchecked Sendable {
    struct Zone {
        var tournament: Tournament?
        var tournamentVersion = 0
        var events: [EventID: (event: ScoreEvent, version: Int)] = [:]
    }

    private let lock = NSLock()
    private var zones: [String: Zone] = [:]
    private var version = 0
    /// While true every call fails, as if the phone had no connection.
    var offlineDevices: Set<String> = []

    func backend(device: String) -> SimulatedBackend { SimulatedBackend(cloud: self, device: device) }

    func withLock<T>(_ body: (inout [String: Zone], inout Int) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&zones, &version)
    }

    var pendingEventCount: Int { withLock { zones, _ in zones.values.reduce(0) { $0 + $1.events.count } } }
}

struct SimulatedBackend: SharedTournamentBackend {
    let cloud: SimulatedCloud
    let device: String

    private func requireOnline() throws {
        if cloud.withLock({ _, _ in cloud.offlineDevices.contains(device) }) { throw SharingError.service("offline") }
    }

    func share(_ tournament: Tournament) async throws -> (zone: SharedZone, url: URL) {
        try requireOnline()
        let name = "tournament-\(tournament.id)"
        cloud.withLock { zones, version in
            version += 1
            zones[name] = SimulatedCloud.Zone(tournament: tournament, tournamentVersion: version)
        }
        return (SharedZone(name: name, owner: device, isOwnedByThisDevice: true), URL(string: "https://example.com/\(name)")!)
    }

    func invitationURL(for zone: SharedZone) async throws -> URL? {
        URL(string: "https://example.com/\(zone.name)")
    }

    func changes(in zone: SharedZone, since token: Data?) async throws -> SharedZoneChanges {
        try requireOnline()
        let since = token.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
        return try cloud.withLock { zones, version in
            guard let data = zones[zone.name] else { throw SharingError.zoneMissing }
            var changes = SharedZoneChanges()
            if data.tournamentVersion > since { changes.tournament = data.tournament }
            // Newest first: the real cloud promises no order, so neither does this one.
            changes.events = data.events.values.filter { $0.version > since }.sorted { $0.version > $1.version }.map(\.event)
            changes.token = Data(String(version).utf8)
            return changes
        }
    }

    func publish(_ tournament: Tournament, in zone: SharedZone) async throws {
        try requireOnline()
        try cloud.withLock { zones, version in
            guard zones[zone.name] != nil else { throw SharingError.zoneMissing }
            version += 1
            zones[zone.name]?.tournament = tournament
            zones[zone.name]?.tournamentVersion = version
        }
    }

    func upload(_ events: [ScoreEvent], to zone: SharedZone) async throws -> [EventID] {
        try requireOnline()
        return try cloud.withLock { zones, version in
            guard zones[zone.name] != nil else { throw SharingError.zoneMissing }
            for event in events {
                version += 1
                zones[zone.name]?.events[event.id] = (event, version)
            }
            return events.map(\.id)
        }
    }

    func removeEvents(_ ids: [EventID], from zone: SharedZone) async throws {
        try requireOnline()
        cloud.withLock { zones, _ in
            for id in ids { zones[zone.name]?.events[id] = nil }
        }
    }

    func removeZone(_ zone: SharedZone) async throws {
        try requireOnline()
        // A guest removing the zone only leaves the share; the organiser deletes it.
        guard zone.isOwnedByThisDevice else { return }
        cloud.withLock { zones, _ in zones[zone.name] = nil }
    }

    /// No pushes here: the tests call `sync()` when a real phone would be woken.
    func subscribeToChanges(ownedByThisDevice: Bool) async throws {}
}

@MainActor
struct Phone {
    let store: TournamentStore
    let sync: SharedTournamentSync

    init(_ name: String, cloud: SimulatedCloud) {
        store = TournamentStore(repository: InMemoryTournamentRepository(), deviceID: DeviceID())
        store.load()
        sync = SharedTournamentSync(store: store, backend: cloud.backend(device: name))
    }
}

private func americano(points: Int = 16) -> TournamentDraft {
    let names = ["Alex", "Lisa", "Johan", "Maja", "Erik", "Daniel", "Sofia", "Fredrik"]
    return TournamentDraft(name: "Friday Padel", configuration: TournamentConfiguration(format: .americano, courtCount: 2, roundCount: 3, scoring: .totalPoints(points)), players: names.map { Player(name: $0) })
}

private func mexicano() -> TournamentDraft {
    let names = ["Alex", "Lisa", "Johan", "Maja", "Erik", "Daniel", "Sofia", "Fredrik"]
    return TournamentDraft(name: "Mexicano", configuration: TournamentConfiguration(format: .mexicano, courtCount: 2, roundCount: 3, scoring: .totalPoints(16)), players: names.map { Player(name: $0) })
}

/// Organiser + two guests that joined the organiser's tournament.
@MainActor
private func sharedSetup(_ draft: TournamentDraft = americano()) async throws -> (cloud: SimulatedCloud, host: Phone, anna: Phone, ben: Phone, id: TournamentID) {
    let cloud = SimulatedCloud()
    let host = Phone("host", cloud: cloud)
    let anna = Phone("anna", cloud: cloud)
    let ben = Phone("ben", cloud: cloud)
    let tournament = try host.store.create(draft)
    _ = try await host.sync.invitationURL(for: tournament.id)
    let zone = SharedZone(name: "tournament-\(tournament.id)", owner: "host", isOwnedByThisDevice: false)
    try await anna.sync.join(zone)
    try await ben.sync.join(zone)
    return (cloud, host, anna, ben, tournament.id)
}

@Suite("Shared tournaments")
@MainActor
struct SharingTests {
    @Test("Joining copies the organiser's tournament as a guest copy")
    func join() async throws {
        let (_, host, anna, _, id) = try await sharedSetup()
        #expect(host.store.tournament(id)?.isHost == true)
        let copy = try #require(anna.store.tournament(id))
        #expect(copy.isGuest)
        #expect(copy.rounds == host.store.tournament(id)?.rounds)
    }

    @Test("Points scored on two guests' phones reach the organiser and every phone")
    func pointsFlowEverywhere() async throws {
        let (cloud, host, anna, ben, id) = try await sharedSetup()
        let round = try #require(host.store.tournament(id)?.rounds.first)
        let court1 = round.matches[0].id
        let court2 = round.matches[1].id

        try anna.store.recordPoint(.a, match: court1, in: id)
        try anna.store.recordPoint(.a, match: court1, in: id)
        try ben.store.recordPoint(.b, match: court2, in: id)
        await anna.sync.sync()
        await ben.sync.sync()
        #expect(cloud.pendingEventCount == 3)

        await host.sync.sync()
        #expect(host.store.tournament(id)?.match(court1)?.score == Score(a: 2, b: 0))
        #expect(host.store.tournament(id)?.match(court2)?.score == Score(a: 0, b: 1))
        #expect(cloud.pendingEventCount == 0, "recorded events are removed once published")

        await anna.sync.sync()
        await ben.sync.sync()
        let hosted = try #require(host.store.tournament(id))
        for phone in [anna, ben] {
            let copy = try #require(phone.store.tournament(id))
            #expect(copy.match(court1)?.score == Score(a: 2, b: 0))
            #expect(copy.match(court2)?.score == Score(a: 0, b: 1))
            #expect(copy.pendingEvents(notIn: hosted).isEmpty)
        }
    }

    @Test("A guest keeps scoring offline; its points are replayed on the organiser's newer state")
    func offlineGuestRebases() async throws {
        let (cloud, host, anna, _, id) = try await sharedSetup()
        let round = try #require(host.store.tournament(id)?.rounds.first)
        cloud.offlineDevices = ["anna"]
        try anna.store.recordPoint(.a, match: round.matches[0].id, in: id)
        try anna.store.recordPoint(.b, match: round.matches[0].id, in: id)
        await anna.sync.sync()
        #expect(anna.sync.errors[id] != nil)

        try host.store.recordPoint(.a, match: round.matches[1].id, in: id)
        await host.sync.sync()

        cloud.offlineDevices = []
        let revisionBefore = try #require(anna.store.tournament(id)?.revision)
        await anna.sync.sync()
        let copy = try #require(anna.store.tournament(id))
        #expect(copy.match(round.matches[0].id)?.score == Score(a: 1, b: 1), "own points kept")
        #expect(copy.match(round.matches[1].id)?.score == Score(a: 1, b: 0), "organiser's point adopted")
        #expect(copy.revision >= revisionBefore, "event ordering never goes backwards")
        #expect(cloud.pendingEventCount == 2)

        await host.sync.sync()
        #expect(host.store.tournament(id)?.match(round.matches[0].id)?.score == Score(a: 1, b: 1))
    }

    @Test("Undo on a guest's phone undoes the point on every phone")
    func undoTravels() async throws {
        let (_, host, anna, _, id) = try await sharedSetup()
        let match = try #require(host.store.tournament(id)?.rounds.first?.matches.first).id
        try anna.store.recordPoint(.a, match: match, in: id)
        try anna.store.recordPoint(.a, match: match, in: id)
        try anna.store.undo(match: match, in: id)
        await anna.sync.sync()
        await host.sync.sync()
        #expect(host.store.tournament(id)?.match(match)?.score == Score(a: 1, b: 0))
    }

    @Test("A point for a match the organiser already finished is kept as a conflict, not lost")
    func conflictIsKept() async throws {
        let (_, host, anna, _, id) = try await sharedSetup()
        let match = try #require(host.store.tournament(id)?.rounds.first?.matches.first).id
        try host.store.enterResult(Score(a: 10, b: 6), match: match, in: id)
        try anna.store.recordPoint(.a, match: match, in: id)
        await anna.sync.sync()
        await host.sync.sync()
        let hosted = try #require(host.store.tournament(id))
        #expect(hosted.match(match)?.score == Score(a: 10, b: 6))
        #expect(hosted.openConflictCount == 1)

        await anna.sync.sync()
        let copy = try #require(anna.store.tournament(id))
        #expect(copy.match(match)?.score == Score(a: 10, b: 6))
        #expect(copy.pendingEvents(notIn: hosted).isEmpty)
    }

    @Test("Only the organiser's phone generates Mexicano rounds")
    func guestsDoNotGenerateRounds() async throws {
        let (_, host, anna, _, id) = try await sharedSetup(mexicano())
        let first = try #require(anna.store.tournament(id)?.rounds.first)
        for (index, match) in first.matches.enumerated() {
            try anna.store.enterResult(index == 0 ? Score(a: 10, b: 6) : Score(a: 7, b: 9), match: match.id, in: id)
        }
        #expect(anna.store.tournament(id)?.rounds.count == 1, "no competing draw on the guest")

        await anna.sync.sync()
        await host.sync.sync()
        #expect(host.store.tournament(id)?.rounds.count == 2)
        await anna.sync.sync()
        #expect(anna.store.tournament(id)?.rounds.map(\.matches) == host.store.tournament(id)?.rounds.map(\.matches))
    }

    @Test("Guests cannot change players or settings")
    func guestIsReadOnlyForManagement() async throws {
        let (_, _, anna, _, id) = try await sharedSetup()
        #expect(throws: StoreError.self) {
            try anna.store.perform(id) { (t, c) throws(TournamentError) in try t.rename("Mine", now: c.now) }
        }
        #expect(throws: StoreError.self) {
            try anna.store.perform(id) { (t, c) throws(TournamentError) in _ = try t.addPlayer(name: "Zoe", context: c) }
        }
    }

    @Test("Points from a guest's watch are forwarded to the organiser")
    func guestWatchEvents() async throws {
        let (_, host, anna, _, id) = try await sharedSetup()
        let match = try #require(host.store.tournament(id)?.rounds.first?.matches.first).id
        let watch = DeviceID()
        let event = ScoreEvent(tournamentID: id, matchID: match, kind: .point(.b), timestamp: Date(), deviceID: watch, deviceSequence: 1, baseRevision: 0)
        let result = anna.store.applyRemote(EventBatch(deviceID: watch, events: [event], sentAt: Date()))
        #expect(result.processed == [event.id])
        await anna.sync.sync()
        await host.sync.sync()
        #expect(host.store.tournament(id)?.match(match)?.score == Score(a: 0, b: 1))
    }

    @Test("When the organiser stops sharing, guests keep their copy as a local tournament")
    func organiserStops() async throws {
        let (_, host, anna, _, id) = try await sharedSetup()
        try await host.sync.stopSharing(id)
        #expect(host.store.tournament(id)?.sharing == nil)
        await anna.sync.sync()
        #expect(anna.store.tournament(id) != nil)
        #expect(anna.store.tournament(id)?.sharing == nil)
        #expect(anna.sync.errors[id] != nil)
    }

    @Test("A guest leaving removes the tournament from that phone only")
    func guestLeaves() async throws {
        let (_, host, anna, ben, id) = try await sharedSetup()
        try await anna.sync.stopSharing(id)
        #expect(anna.store.tournament(id) == nil)
        #expect(host.store.tournament(id) != nil)
        #expect(ben.store.tournament(id) != nil)
    }

    @Test("Tournaments saved before sharing existed still load")
    func oldFilesDecode() throws {
        let store = TournamentStore(repository: InMemoryTournamentRepository(), deviceID: DeviceID())
        let tournament = try store.create(americano())
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(tournament)) as? [String: Any])
        json["sharing"] = nil
        let decoded = try JSONDecoder().decode(Tournament.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.sharing == nil)
        #expect(decoded.rounds == tournament.rounds)
    }
}
