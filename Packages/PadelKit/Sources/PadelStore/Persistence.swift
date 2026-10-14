import Foundation
import PadelCore

public enum PersistenceError: Error, Equatable, Sendable, CustomStringConvertible {
    case writeFailed(String)
    case readFailed(String)
    case corrupt(String)
    case newerSchema(found: Int, supported: Int)

    public var description: String {
        switch self {
        case .writeFailed(let detail): L10n.format("Could not save: %@", detail)
        case .readFailed(let detail): L10n.format("Could not read saved data: %@", detail)
        case .corrupt(let detail): L10n.format("Saved data is damaged: %@", detail)
        case .newerSchema(let found, let supported): L10n.format("Saved by a newer version of the app (format %lld, this version reads up to %lld).", found, supported)
        }
    }
}

/// Versioned wrapper for every file written to disk.
struct Envelope<Value: Codable>: Codable {
    var schemaVersion: Int
    var savedAt: Date
    var value: Value
}

private struct VersionProbe: Decodable {
    var schemaVersion: Int
}

/// Reads and writes one JSON document atomically (write to a temporary file, then
/// rename), so a crash mid-write can never leave a half-written file behind.
public struct JSONFileStore<Value: Codable>: Sendable {
    public let url: URL
    public let schemaVersion: Int
    /// Upgrades raw JSON written with an older schema version to the current one.
    let migrate: @Sendable (_ data: Data, _ fromVersion: Int) throws -> Data

    public init(url: URL, schemaVersion: Int, migrate: @escaping @Sendable (Data, Int) throws -> Data = { data, _ in data }) {
        self.url = url
        self.schemaVersion = schemaVersion
        self.migrate = migrate
    }

    public func load() throws(PersistenceError) -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .readFailed(error.localizedDescription)
        }
        return try Self.decode(data, schemaVersion: schemaVersion, migrate: migrate)
    }

    static func decode(_ data: Data, schemaVersion: Int, migrate: (Data, Int) throws -> Data) throws(PersistenceError) -> Value {
        let decoder = JSONDecoder()
        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
        } catch {
            throw .corrupt("missing schema version")
        }
        if version > schemaVersion { throw .newerSchema(found: version, supported: schemaVersion) }
        do {
            let current = version < schemaVersion ? try migrate(data, version) : data
            return try decoder.decode(Envelope<Value>.self, from: current).value
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw .corrupt(String(describing: error))
        }
    }

    public func save(_ value: Value, now: Date = Date()) throws(PersistenceError) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(Envelope(schemaVersion: schemaVersion, savedAt: now, value: value))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
    }

    public func delete() throws(PersistenceError) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
    }
}

// MARK: - Tournament repository

public struct RepositoryLoadResult: Sendable {
    public var tournaments: [Tournament]
    /// Human-readable problems found while loading (damaged or newer files). Nothing is
    /// deleted: damaged files are moved aside so they can be recovered.
    public var issues: [String]
}

public protocol TournamentRepository: Sendable {
    func loadAll() -> RepositoryLoadResult
    func save(_ tournament: Tournament) throws(PersistenceError)
    func delete(_ id: TournamentID) throws(PersistenceError)
}

public enum TournamentSchema {
    /// Version 1: initial format.
    public static let currentVersion = 1

    /// Upgrade path for older files. Each step transforms raw JSON from version n to n+1.
    public static func migrate(_ data: Data, from version: Int) throws -> Data {
        // Add a case per schema bump, transforming raw JSON from version n to n + 1, e.g.
        //   case 1: data = try migrateV1toV2(data)
        // Version 1 is the first released format, so there is nothing to upgrade yet.
        guard version == currentVersion else {
            throw PersistenceError.corrupt("no migration from schema \(version)")
        }
        return data
    }
}

/// One JSON file per tournament, so saving a score rewrites only that tournament.
public final class FileTournamentRepository: TournamentRepository, @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()

    public init(directory: URL) {
        self.directory = directory
    }

    /// `Application Support/Tournaments` in the app container.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Tournaments", isDirectory: true)
    }

    private func store(for id: TournamentID) -> JSONFileStore<Tournament> {
        JSONFileStore(url: directory.appendingPathComponent("\(id.rawValue.uuidString).json"), schemaVersion: TournamentSchema.currentVersion, migrate: TournamentSchema.migrate)
    }

    public func loadAll() -> RepositoryLoadResult {
        lock.lock(); defer { lock.unlock() }
        var tournaments: [Tournament] = []
        var issues: [String] = []
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            let store = JSONFileStore<Tournament>(url: file, schemaVersion: TournamentSchema.currentVersion, migrate: TournamentSchema.migrate)
            do {
                if var tournament = try store.load() {
                    let repaired = tournament.repairCaches()
                    if repaired > 0 { issues.append(L10n.format("Recalculated %lld match scores in %@.", repaired, tournament.name)) }
                    tournaments.append(tournament)
                }
            } catch .newerSchema(let found, let supported) {
                issues.append(L10n.format("%@ was saved by a newer app version (%lld > %lld). Update the app to open it.", file.lastPathComponent, found, supported))
            } catch {
                issues.append(L10n.format("A saved tournament could not be read and was set aside (%@).", "\(error)"))
                quarantine(file)
            }
        }
        return RepositoryLoadResult(tournaments: tournaments, issues: issues)
    }

    private func quarantine(_ file: URL) {
        let folder = directory.appendingPathComponent("Quarantine", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(file.lastPathComponent)")
        try? FileManager.default.moveItem(at: file, to: target)
    }

    public func save(_ tournament: Tournament) throws(PersistenceError) {
        lock.lock(); defer { lock.unlock() }
        try store(for: tournament.id).save(tournament, now: tournament.updatedAt)
    }

    public func delete(_ id: TournamentID) throws(PersistenceError) {
        lock.lock(); defer { lock.unlock() }
        try store(for: id).delete()
    }
}

/// Repository for tests and previews, with failure injection.
public final class InMemoryTournamentRepository: TournamentRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TournamentID: Data] = [:]
    public var failNextSave = false
    public var failAllSaves = false
    public private(set) var saveCount = 0

    public init(_ tournaments: [Tournament] = []) {
        for tournament in tournaments { storage[tournament.id] = try? JSONEncoder().encode(tournament) }
    }

    public func loadAll() -> RepositoryLoadResult {
        lock.lock(); defer { lock.unlock() }
        let tournaments = storage.values.compactMap { try? JSONDecoder().decode(Tournament.self, from: $0) }
        return RepositoryLoadResult(tournaments: tournaments, issues: [])
    }

    public func save(_ tournament: Tournament) throws(PersistenceError) {
        lock.lock(); defer { lock.unlock() }
        if failNextSave || failAllSaves {
            failNextSave = false
            throw .writeFailed("simulated failure")
        }
        guard let data = try? JSONEncoder().encode(tournament) else { throw .writeFailed("encoding") }
        storage[tournament.id] = data
        saveCount += 1
    }

    public func delete(_ id: TournamentID) throws(PersistenceError) {
        lock.lock(); defer { lock.unlock() }
        storage[id] = nil
    }

    public func stored(_ id: TournamentID) -> Tournament? {
        lock.lock(); defer { lock.unlock() }
        return storage[id].flatMap { try? JSONDecoder().decode(Tournament.self, from: $0) }
    }
}
