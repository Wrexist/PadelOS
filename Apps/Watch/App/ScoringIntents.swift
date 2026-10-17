import AppIntents

/// Opens the watch app straight on the active match. Exposed as an App Shortcut so it can
/// be assigned to the Apple Watch Ultra Action button (Settings → Action Button →
/// Shortcut) or run from Siri. The app does not intercept the Action button itself.
struct OpenActiveMatchIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Active Match"
    static let description = IntentDescription("Shows the padel match you are scoring.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchRouter.shared.openActiveMatchRequest += 1
        return .result()
    }
}

struct PadelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenActiveMatchIntent(),
            phrases: ["Open my \(.applicationName) match", "Score padel in \(.applicationName)"], // l10n-ignore: App Shortcut phrases need an AppShortcuts.xcstrings catalog; English only for now (PROJECT_STATUS)
            shortTitle: "Active Match",
            systemImageName: "sportscourt"
        )
    }
}
