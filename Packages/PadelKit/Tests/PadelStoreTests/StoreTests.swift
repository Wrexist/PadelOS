import Foundation
import Testing
@testable import PadelCore
@testable import PadelSync
@testable import PadelStore

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("padel-store-\(UUID().uuidString)", isDirectory: true)
}

private func draft(format: TournamentFormat = .americano, players: Int = 8) -> TournamentDraft {
    let names = ["Alex", "Lisa", "Johan", "Maja", "Erik", "Daniel", "Sofia", "Fredrik"]
    return TournamentDraft(name: "Friday Padel", configuration: TournamentConfiguration(format: format, courtCount: 2, roundCount: 3, scoring: .totalPoints(24)), players: (0..<players).map { Player(name: names[$0]) })
}

@Suite("Persistence")
@MainActor
struct PersistenceTests {
    @Test("Tournaments survive closing and reopening the app")
    func survivesRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = DeviceID()
        let store = TournamentStore(repository: FileTournamentRepository(directory: directory), deviceID: device)
        store.load()
        let t = try store.create(draft())
        let match = t.rounds[0].matches[0].id
        try store.recordPoint(.a, match: match, in: t.id)
        try store.recordPoint(.b, match: match, in: t.id)
        try store.undo(match: match, in: t.id)

        let reopened = TournamentStore(repository: FileTournamentRepository(directory: directory), deviceID: device)
        reopened.load()
        #expect(reopened.loadIssues.isEmpty)
        #expect(reopened.tournaments == store.tournaments)
        #expect(reopened.tournament(t.id)?.match(match)?.score == Score(a: 1, b: 0))
        #expect(reopened.resumableTournament?.id == t.id)
    }

    @Test("A damaged file is set aside and reported; other tournaments still load")
    func corruptFileQuarantined() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileTournamentRepository(directory: directory)
        let store = TournamentStore(repository: repository, deviceID: DeviceID())
        store.load()
        _ = try store.create(draft())
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent("\(UUID().uuidString).json"))
        let result = repository.loadAll()
        #expect(result.tournaments.count == 1)
        #expect(result.issues.count == 1)
        let quarantine = directory.appendingPathComponent("Quarantine")
        #expect((try? FileManager.default.contentsOfDirectory(atPath: quarantine.path))?.count == 1)
    }

    @Test("Files from a newer app version are reported and left untouched")
    func newerSchema() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(UUID().uuidString).json")
        try Data(#"{"schemaVersion": 99, "savedAt": 0, "value": {}}"#.utf8).write(to: file)
        let result = FileTournamentRepository(directory: directory).loadAll()
        #expect(result.tournaments.isEmpty)
        #expect(result.issues.first?.contains("newer app version") == true)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Damaged cached scores are recalculated from the event log on load")
    func repairsCache() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileTournamentRepository(directory: directory)
        let store = TournamentStore(repository: repository, deviceID: DeviceID())
        store.load()
        let t = try store.create(draft())
        let match = t.rounds[0].matches[0].id
        try store.recordPoint(.a, match: match, in: t.id)
        // Tamper with the cached score on disk.
        let url = directory.appendingPathComponent("\(t.id.rawValue.uuidString).json")
        var json = try String(contentsOf: url, encoding: .utf8)
        json = json.replacingOccurrences(of: #""score":{"a":1,"b":0}"#, with: #""score":{"a":9,"b":0}"#)
        try json.write(to: url, atomically: true, encoding: .utf8)
        let result = repository.loadAll()
        #expect(result.tournaments.first?.match(match)?.score == Score(a: 1, b: 0))
        #expect(result.issues.count == 1)
    }

    @Test("A failed save leaves the visible state unchanged")
    func atomicFailure() throws {
        let repository = InMemoryTournamentRepository()
        let store = TournamentStore(repository: repository, deviceID: DeviceID())
        store.load()
        let t = try store.create(draft())
        let match = t.rounds[0].matches[0].id
        let before = store.tournament(t.id)
        repository.failNextSave = true
        #expect(throws: StoreError.self) { try store.recordPoint(.a, match: match, in: t.id) }
        #expect(store.tournament(t.id) == before)
        #expect(repository.stored(t.id) == before)
        try store.recordPoint(.a, match: match, in: t.id)
        #expect(repository.stored(t.id)?.match(match)?.score == Score(a: 1, b: 0))
    }

    @Test("Domain errors are reported and nothing is saved")
    func domainErrors() throws {
        let repository = InMemoryTournamentRepository()
        let store = TournamentStore(repository: repository, deviceID: DeviceID())
        store.load()
        #expect(throws: StoreError.self) { try store.create(draft(players: 3)) }
        let t = try store.create(draft())
        let saves = repository.saveCount
        #expect(throws: StoreError.self) { try store.undo(match: t.rounds[0].matches[0].id, in: t.id) }
        #expect(repository.saveCount == saves)
    }

    @Test("Settings tolerate missing keys and keep the sync sequence monotonic")
    func settings() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = JSONFileStore<AppSettings>(url: directory.appendingPathComponent("Settings.json"), schemaVersion: 1)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion": 1, "savedAt": 0, "value": {"defaultPoints": 32}}"#.utf8).write(to: file.url)
        let store = SettingsStore(file: file)
        #expect(store.settings.defaultPoints == 32)
        #expect(store.settings.defaultCourtCount == 2)
        #expect(!store.settings.hasCompletedOnboarding)
        store.update { $0.hasCompletedOnboarding = true }
        #expect(SettingsStore(file: file).settings.hasCompletedOnboarding)
        let a = store.nextSyncSequence(), b = store.nextSyncSequence()
        #expect(b > a)
        let reloaded = SettingsStore(file: file)
        #expect(reloaded.settings.syncSequence == b)
        #expect(reloaded.settings.phoneInstanceID == store.settings.phoneInstanceID)
        reloaded.update { $0.rememberNames(["Alex", "lisa", "Alex"]) }
        reloaded.update { $0.rememberNames(["Lisa", "Johan"]) }
        #expect(reloaded.settings.recentPlayerNames.prefix(3) == ["Lisa", "Johan", "Alex"])
    }
}

@Suite("User journey")
@MainActor
struct JourneyTests {
    /// Create → add players → schedule → score → undo → finish → standings → restart app →
    /// resume → correct → finish tournament → share.
    @Test("Complete organiser journey with persistence")
    func journey() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = DeviceID()
        var store = TournamentStore(repository: FileTournamentRepository(directory: directory), deviceID: device)
        store.load()
        let t = try store.create(draft())
        #expect(t.rounds.count == 3)
        let first = t.rounds[0].matches[0]
        for _ in 0..<15 { try store.recordPoint(.a, match: first.id, in: t.id) }
        for _ in 0..<9 { try store.recordPoint(.b, match: first.id, in: t.id) }
        #expect(throws: StoreError.self) { try store.recordPoint(.b, match: first.id, in: t.id) } // total reached
        try store.undo(match: first.id, in: t.id)
        try store.recordPoint(.b, match: first.id, in: t.id)
        try store.finish(match: first.id, in: t.id)
        var standings = StandingsCalculator.compute(store.tournament(t.id)!)
        #expect(standings.entry(for: .player(first.sideA.playerIDs[0]))?.points == 15)

        // App closed and reopened.
        store = TournamentStore(repository: FileTournamentRepository(directory: directory), deviceID: device)
        store.load()
        let resumed = try #require(store.resumableTournament)
        #expect(resumed.id == t.id)
        try store.enterResult(Score(a: 10, b: 14), match: first.id, in: t.id)
        standings = StandingsCalculator.compute(store.tournament(t.id)!)
        #expect(standings.entry(for: .player(first.sideA.playerIDs[0]))?.points == 10)

        for round in store.tournament(t.id)!.rounds {
            for match in round.matches where !match.isCompleted {
                try store.enterResult(Score(a: 12, b: 12), match: match.id, in: t.id)
            }
        }
        #expect(store.tournament(t.id)?.allRoundsCompleted == true)
        try store.perform(t.id) { (t, c) throws(TournamentError) in t.finish(now: c.now) }
        #expect(store.tournament(t.id)?.status == .completed)
        let text = ResultSummary.text(for: store.tournament(t.id)!)
        #expect(text.contains("Final standings"))
        #expect(text.contains("Friday Padel"))
    }
}

@Suite("Change observers")
@MainActor
struct ChangeObserverTests {
    @Test("Both onChange and additional observers are told about saved changes only")
    func observers() throws {
        let store = TournamentStore(repository: InMemoryTournamentRepository(), deviceID: DeviceID())
        store.load()
        var primary = 0, extra = 0
        store.onChange = { primary += 1 }
        store.addChangeObserver { extra += 1 }
        let t = try store.create(draft())
        try store.recordPoint(.a, match: t.rounds[0].matches[0].id, in: t.id)
        #expect(throws: StoreError.self) { try store.undo(match: t.rounds[0].matches[1].id, in: t.id) }
        #expect(primary == 2 && extra == 2)
    }
}
