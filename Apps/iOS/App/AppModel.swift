import CloudKit
import Foundation
import Observation
import UIKit
import PadelCore
import PadelStore
import PadelSync

/// Composition root: owns the stores and the watch connection. Passed explicitly through
/// the SwiftUI environment instead of hidden singletons.
@MainActor
@Observable
final class AppModel {
    /// Single instance shared by the SwiftUI scene and the Live Activity intents, which
    /// can run before any UI exists.
    static let shared = AppModel()

    let settings: SettingsStore
    let store: TournamentStore
    let sync: PhoneSyncCoordinator
    let watchTransport: WatchConnectivityTransport?
    let liveActivities: LiveActivityController
    /// Tournaments shared with other phones through iCloud.
    let sharedSync: SharedTournamentSync
    /// Public spectator boards ("Share Live Leaderboard").
    let liveBoards: LiveBoardPublisher
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var sharedSyncScheduled = false
    @ObservationIgnored private var sharedPolling: Task<Void, Never>?
    @ObservationIgnored private var liveBoardBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var isRegisteredForPush = false

    /// A tournament to show (set after accepting an invitation).
    var openTournamentRequest: TournamentID?

    /// Error shown in a banner on the current screen.
    var errorMessage: String?
    /// Short confirmation with optional undo ("Point to Team A").
    var toast: Toast?

    struct Toast: Equatable {
        let id = UUID()
        var message: String
        var undo: UndoAction?

        static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    struct UndoAction {
        var title: String
        var perform: () -> Void
    }

    /// True when launched by UI tests: data lives in a fresh temporary folder.
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing") }

    init() {
        let tournamentsDirectory: URL
        let settingsFile: JSONFileStore<AppSettings>
        if Self.isUITesting {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("PadelOS-UITests", isDirectory: true)
            if ProcessInfo.processInfo.arguments.contains("-reset-data") {
                try? FileManager.default.removeItem(at: root)
            }
            tournamentsDirectory = root.appendingPathComponent("Tournaments", isDirectory: true)
            settingsFile = JSONFileStore(url: root.appendingPathComponent("Settings.json"), schemaVersion: AppSettings.schemaVersion)
        } else {
            tournamentsDirectory = FileTournamentRepository.defaultDirectory()
            settingsFile = SettingsStore.defaultFile()
        }
        let settings = SettingsStore(file: settingsFile)
        let store = TournamentStore(repository: FileTournamentRepository(directory: tournamentsDirectory), deviceID: settings.settings.deviceID)
        let transport = WatchConnectivityTransport()
        self.settings = settings
        self.store = store
        self.watchTransport = transport.isSupported ? transport : nil
        if transport.isSupported {
            self.sync = PhoneSyncCoordinator(store: store, settings: settings, transport: transport)
        } else {
            self.sync = PhoneSyncCoordinator(store: store, settings: settings, transport: InMemorySyncTransport())
        }
        self.liveActivities = LiveActivityController(store: store, isEnabled: { settings.settings.liveActivitiesEnabled })
        // CloudKit is only touched once a tournament is shared, so UI tests and unsigned
        // builds never need the iCloud entitlement.
        self.sharedSync = SharedTournamentSync(store: store, backend: CloudKitSharedBackend())
        // Likewise, the public database is only used once a board is shared.
        self.liveBoards = LiveBoardPublisher(store: store, backend: CloudKitLiveBoardBackend())
    }

    /// Loads data and connects the watch. Safe to call more than once.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        store.load()
        if Self.isUITesting && ProcessInfo.processInfo.arguments.contains("-demo-playoffs") && store.tournaments.isEmpty {
            seedPlayoffDemo()
        }
        sync.start()
        let liveActivities = liveActivities
        store.addChangeObserver {
            Task { await liveActivities.refresh() }
        }
        store.addChangeObserver { [weak self] in
            self?.scheduleSharedSync()
        }
        store.addChangeObserver { [weak self] in
            self?.liveBoardsDidChange()
        }
        Task { await liveActivities.refresh() }
        let liveBoards = liveBoards
        Task { await liveBoards.resume() }
        // Apple asks for registration on every launch; CloudKit keeps the device token.
        registerForPushIfNeeded()
    }

    // MARK: Shared tournaments

    /// Syncs shared tournaments shortly after a change (a burst of taps becomes one upload).
    /// Also runs when a watch point wakes the app in the background.
    func scheduleSharedSync() {
        guard sharedSync.hasSharedTournaments else { return }
        registerForPushIfNeeded()
        guard !sharedSyncScheduled else { return }
        sharedSyncScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            sharedSyncScheduled = false
            await runSharedSync()
        }
    }

    private func runSharedSync() async {
        let application = UIApplication.shared
        let task = application.beginBackgroundTask(withName: "Shared tournament sync")
        await sharedSync.sync()
        if task != .invalid { application.endBackgroundTask(task) }
    }

    /// CloudKit wakes the app with a silent push when another phone changes a shared
    /// tournament (the subscriptions are made by `SharedTournamentSync`). Silent pushes
    /// need no permission prompt. Only once this phone has a shared tournament.
    private func registerForPushIfNeeded() {
        guard !isRegisteredForPush, sharedSync.hasSharedTournaments else { return }
        isRegisteredForPush = true
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// A silent push from CloudKit: brings shared tournaments up to date while the app is
    /// in the background (the organiser's phone in a bag picks up other courts' points).
    func syncForRemoteNotification() async -> UIBackgroundFetchResult {
        start()
        guard sharedSync.hasSharedTournaments else { return .noData }
        let before = sharedRevisions
        await runSharedSync()
        if sharedRevisions != before { return .newData }
        return sharedSync.errors.isEmpty ? .noData : .failed
    }

    private var sharedRevisions: [TournamentID: Int] {
        Dictionary(uniqueKeysWithValues: store.tournaments.filter { $0.sharing != nil }.map { ($0.id, $0.revision) })
    }

    /// While the app is on screen, other phones' points arrive every few seconds.
    func sceneDidChange(isActive: Bool) {
        sharedPolling?.cancel()
        sharedPolling = nil
        guard isActive else { return }
        sharedPolling = Task { [weak self] in
            while !Task.isCancelled {
                if let self, self.sharedSync.hasSharedTournaments {
                    await self.runSharedSync()
                }
                // Retries spectator boards whose last upload failed (no-op otherwise).
                if let self, self.liveBoards.hasBoards {
                    await self.liveBoards.sync()
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: Spectator boards

    /// Republishes shared boards shortly after a change (the publisher coalesces a burst
    /// of points). A watch point can wake the app in the background, so the upload gets
    /// background time like the shared sync does.
    private func liveBoardsDidChange() {
        guard liveBoards.hasBoards else { return }
        liveBoards.storeDidChange()
        guard liveBoardBackgroundTask == .invalid else { return }
        liveBoardBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Live leaderboard") { [weak self] in
            self?.endLiveBoardBackgroundTask()
        }
        let liveBoards = liveBoards
        Task { [weak self] in
            await liveBoards.waitUntilIdle()
            self?.endLiveBoardBackgroundTask()
        }
    }

    private func endLiveBoardBackgroundTask() {
        guard liveBoardBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(liveBoardBackgroundTask)
        liveBoardBackgroundTask = .invalid
    }

    /// Opens an invitation link: joins the tournament (or, for the organiser's own link,
    /// just shows it).
    func acceptInvitation(_ metadata: CKShare.Metadata) async {
        let zoneID = metadata.share.recordID.zoneID
        do {
            if metadata.participantRole == .owner {
                openTournamentRequest = TournamentID(uuidString: String(zoneID.zoneName.dropFirst("tournament-".count)))
                return
            }
            _ = try await CKContainer(identifier: metadata.containerIdentifier).accept(metadata)
            let zone = SharedZone(name: zoneID.zoneName, owner: zoneID.ownerName, isOwnedByThisDevice: false)
            openTournamentRequest = try await sharedSync.join(zone)
            showToast(String(localized: "You joined the tournament."))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// UI tests only: a tournament whose regular rounds are played, so the semifinals
    /// and the bracket are on screen.
    private func seedPlayoffDemo() {
        let names = ["Alex", "Lisa", "Johan", "Maja", "Erik", "Sofia", "Daniel", "Nora"]
        let configuration = TournamentConfiguration(format: .americano, courtCount: 2, roundCount: 3, scoring: .totalPoints(16), playoff: .semifinals)
        let draft = TournamentDraft(name: "Friday Playoffs", configuration: configuration, players: names.map { Player(name: $0) })
        guard let tournament = try? store.create(draft) else { return }
        var scores = [Score(a: 10, b: 6), Score(a: 7, b: 9), Score(a: 12, b: 4), Score(a: 8, b: 8), Score(a: 5, b: 11), Score(a: 9, b: 7)]
        while let current = store.tournament(tournament.id)?.currentRound, current.number <= configuration.roundCount {
            for match in current.matches where !match.isCompleted {
                let score = scores.isEmpty ? Score(a: 9, b: 7) : scores.removeFirst()
                try? store.enterResult(score, match: match.id, in: tournament.id)
            }
            if store.tournament(tournament.id)?.currentRound?.number == current.number { break }
        }
    }

    /// Runs a store command, turning failures into a visible message.
    @discardableResult
    func run(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return false
        }
    }

    func showToast(_ message: String, undo: UndoAction? = nil) {
        toast = Toast(message: message, undo: undo)
    }

    // MARK: Watch status for the UI

    enum WatchStatus: Equatable {
        case notSupported
        case notInstalled
        case reachable
        case notReachable
    }

    var watchStatus: WatchStatus {
        guard let transport = watchTransport else { return .notSupported }
        if !transport.isCounterpartAppInstalled { return .notInstalled }
        return transport.isReachable ? .reachable : .notReachable
    }
}
