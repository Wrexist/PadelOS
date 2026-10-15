import CloudKit
import SwiftUI
import UIKit
import PadelCore
import PadelStore

@main
struct PadelOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.store)
                .environment(model.settings)
                .tint(Theme.Colors.accentText)
                .task { model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.sync.publish() }
                    model.sceneDidChange(isActive: phase == .active)
                }
        }
    }
}

/// Only needed to receive tournament invitations: iOS hands an accepted iCloud share to
/// the window scene's delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata { accept(metadata) }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        accept(cloudKitShareMetadata)
    }

    private func accept(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            AppModel.shared.start()
            await AppModel.shared.acceptInvitation(metadata)
        }
    }
}

/// Navigation destinations.
enum Route: Hashable {
    case tournament(TournamentID)
    case match(TournamentID, MatchID)
    case settings
    /// Leaderboard of every player across tournaments.
    case players
    /// One player's statistics and history (players are matched by name).
    case player(PlayerKey)
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var path: [Route] = []

    /// Shown on first launch. UI tests skip it unless they ask for it with `-show-onboarding`.
    private var showsOnboarding: Bool {
        if onboardingDismissedThisLaunch { return false }
        if ProcessInfo.processInfo.arguments.contains("-show-onboarding") { return true }
        return !AppModel.isUITesting && !settings.settings.hasCompletedOnboarding
    }
    @State private var onboardingDismissedThisLaunch = false

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .tournament(let id):
                        TournamentView(tournamentID: id, path: $path)
                    case .match(let tournamentID, let matchID):
                        MatchScoringView(tournamentID: tournamentID, matchID: matchID)
                    case .settings:
                        SettingsView()
                    case .players:
                        PlayersView(path: $path)
                    case .player(let key):
                        PlayerDetailView(key: key, path: $path)
                    }
                }
        }
        .overlay(alignment: .bottom) {
            ToastHost()
        }
        .onOpenURL { url in
            // padelos://match/<tournament>/<match> from the Live Activity.
            let parts = url.pathComponents.filter { $0 != "/" }
            guard url.scheme == "padelos", url.host == "match", parts.count == 2,
                  let tournament = TournamentID(uuidString: parts[0]),
                  let match = MatchID(uuidString: parts[1]) else { return }
            path = [.tournament(tournament), .match(tournament, match)]
        }
        .preferredColorScheme(nil)
        .onChange(of: model.openTournamentRequest) { _, id in
            guard let id else { return }
            path = [.tournament(id)]
            model.openTournamentRequest = nil
        }
        .fullScreenCover(isPresented: Binding(get: { showsOnboarding }, set: { _ in })) {
            OnboardingView {
                onboardingDismissedThisLaunch = true
                settings.update { $0.hasCompletedOnboarding = true }
            }
        }
    }
}

/// Presents `AppModel.toast` for a few seconds.
struct ToastHost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let toast = model.toast {
                ToastView(message: toast.message, actionTitle: toast.undo?.title) {
                    toast.undo?.perform()
                    model.toast = nil
                }
                .padding(.bottom, Theme.Spacing.xl)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(4))
                    if model.toast?.id == toast.id { model.toast = nil }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }
}
