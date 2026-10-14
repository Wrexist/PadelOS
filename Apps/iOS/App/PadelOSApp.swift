import SwiftUI
import PadelCore
import PadelStore

@main
struct PadelOSApp: App {
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
                }
        }
    }
}

/// Navigation destinations.
enum Route: Hashable {
    case tournament(TournamentID)
    case match(TournamentID, MatchID)
    case settings
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []

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
