import Foundation

/// The few values a watch complication needs, written by the watch app into the shared
/// App Group container and read by the widget extension. Kept deliberately tiny and
/// independent of PadelKit so the extension stays lightweight.
struct ActiveMatchSnapshot: Codable, Equatable {
    var tournamentName: String
    var roundLabel: String
    var court: Int
    var teamA: String
    var teamB: String
    var scoreA: Int
    var scoreB: Int
    /// Fixed match total, or nil for timed matches.
    var total: Int?
    var isFinished: Bool

    /// Derived from the bundle ID at build time (`PadelAppGroup` in Info.plist), so changing
    /// `PADEL_BUNDLE_ID` keeps the watch app and the complication on the same group.
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "PadelAppGroup") as? String ?? "group.app.padelos.PadelOS"
    private static let key = "activeMatchSnapshot"

    /// Shared defaults when the App Group entitlement is present (signed builds);
    /// otherwise nil, and the complication shows its placeholder.
    private static var defaults: UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil else { return nil }
        return UserDefaults(suiteName: appGroup)
    }

    static func load() -> ActiveMatchSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ActiveMatchSnapshot.self, from: data)
    }

    /// Saves and reports whether anything changed (so callers only reload when needed).
    @discardableResult
    static func store(_ snapshot: ActiveMatchSnapshot?) -> Bool {
        guard let defaults else { return false }
        guard snapshot != load() else { return false }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        return true
    }

    static let preview = ActiveMatchSnapshot(tournamentName: "Friday Padel", roundLabel: "R2/6", court: 1, teamA: "Alex/Johan", teamB: "Lisa/Maja", scoreA: 12, scoreB: 8, total: 24, isFinished: false)
}
