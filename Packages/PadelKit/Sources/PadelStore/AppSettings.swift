import Foundation
import Observation
import PadelCore

/// User preferences and device identity. Decoding tolerates missing keys so new
/// settings can be added without a migration.
public struct AppSettings: Codable, Hashable, Sendable {
    public static let schemaVersion = 1
    public static let recentNameLimit = 40
    public static let unroutableLimit = 200

    public var defaultFormat: TournamentFormat
    public var defaultCourtCount: Int
    public var defaultPoints: Int
    public var hapticsEnabled: Bool
    public var keepScreenAwakeWhileScoring: Bool
    /// Show the match being scored as a Live Activity (Lock Screen / Dynamic Island).
    public var liveActivitiesEnabled: Bool
    /// Names typed recently, newest first, for quick re-entry.
    public var recentPlayerNames: [String]
    public var deviceID: DeviceID
    public var phoneInstanceID: UUID
    /// Last snapshot sequence sent to the watch. Persisted so it stays monotonic.
    public var syncSequence: Int
    /// Watch events for tournaments that no longer exist. Kept, not discarded.
    public var unroutableEvents: [ScoreConflict]

    public init(deviceID: DeviceID = DeviceID(), phoneInstanceID: UUID = UUID()) {
        defaultFormat = .americano
        defaultCourtCount = 2
        defaultPoints = 24
        hapticsEnabled = true
        keepScreenAwakeWhileScoring = true
        liveActivitiesEnabled = true
        recentPlayerNames = []
        self.deviceID = deviceID
        self.phoneInstanceID = phoneInstanceID
        syncSequence = 0
        unroutableEvents = []
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        defaultFormat = (try? c.decodeIfPresent(TournamentFormat.self, forKey: .defaultFormat)) ?? defaults.defaultFormat
        defaultCourtCount = (try? c.decodeIfPresent(Int.self, forKey: .defaultCourtCount)) ?? defaults.defaultCourtCount
        defaultPoints = (try? c.decodeIfPresent(Int.self, forKey: .defaultPoints)) ?? defaults.defaultPoints
        hapticsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled)) ?? defaults.hapticsEnabled
        keepScreenAwakeWhileScoring = (try? c.decodeIfPresent(Bool.self, forKey: .keepScreenAwakeWhileScoring)) ?? defaults.keepScreenAwakeWhileScoring
        liveActivitiesEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .liveActivitiesEnabled)) ?? defaults.liveActivitiesEnabled
        recentPlayerNames = (try? c.decodeIfPresent([String].self, forKey: .recentPlayerNames)) ?? []
        deviceID = (try? c.decodeIfPresent(DeviceID.self, forKey: .deviceID)) ?? defaults.deviceID
        phoneInstanceID = (try? c.decodeIfPresent(UUID.self, forKey: .phoneInstanceID)) ?? defaults.phoneInstanceID
        syncSequence = (try? c.decodeIfPresent(Int.self, forKey: .syncSequence)) ?? 0
        unroutableEvents = (try? c.decodeIfPresent([ScoreConflict].self, forKey: .unroutableEvents)) ?? []
    }

    public mutating func rememberNames(_ names: [String]) {
        var result = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for name in recentPlayerNames where !result.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            result.append(name)
        }
        recentPlayerNames = Array(result.prefix(Self.recentNameLimit))
    }
}

@MainActor
@Observable
public final class SettingsStore {
    public private(set) var settings: AppSettings
    public private(set) var lastError: String?
    @ObservationIgnored private let file: JSONFileStore<AppSettings>?

    public init(file: JSONFileStore<AppSettings>?) {
        self.file = file
        var loaded: AppSettings?
        do {
            loaded = try file?.load()
        } catch {
            lastError = error.description
        }
        let initial = loaded ?? AppSettings()
        settings = initial
        if loaded == nil { try? file?.save(initial) }
    }

    public static func defaultFile() -> JSONFileStore<AppSettings> {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return JSONFileStore(url: base.appendingPathComponent("Settings.json"), schemaVersion: AppSettings.schemaVersion)
    }

    /// Applies a change and saves it. Settings stay changed in memory even if saving fails
    /// (they are preferences), but the error is reported.
    public func update(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        settings = copy
        do {
            try file?.save(copy)
            lastError = nil
        } catch {
            lastError = error.description
        }
    }

    /// Next snapshot sequence; persisted before use so it never goes backwards.
    public func nextSyncSequence() -> Int {
        update { $0.syncSequence += 1 }
        return settings.syncSequence
    }

    public func recordUnroutable(_ conflicts: [ScoreConflict]) {
        guard !conflicts.isEmpty else { return }
        update { settings in
            let known = Set(settings.unroutableEvents.map(\.id))
            settings.unroutableEvents += conflicts.filter { !known.contains($0.id) }
            if settings.unroutableEvents.count > AppSettings.unroutableLimit {
                settings.unroutableEvents.removeFirst(settings.unroutableEvents.count - AppSettings.unroutableLimit)
            }
        }
    }
}
