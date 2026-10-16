import SwiftUI
import PadelCore
import PadelStore

enum WatchRoute: Hashable {
    case scoring(TournamentID, MatchID)
    case courts(TournamentID)
    case standings(TournamentID)
}

struct WatchRootView: View {
    @Environment(WatchModel.self) private var model
    @Environment(WatchStore.self) private var store
    @Environment(WatchRouter.self) private var router
    @State private var path: [WatchRoute] = []

    var body: some View {
        Group {
            if WatchDemo.showsComplicationGallery {
                ComplicationGalleryView()
            } else {
                NavigationStack(path: $path) {
                    WatchHomeView(path: $path)
                        .navigationDestination(for: WatchRoute.self) { route in
                            switch route {
                            case .scoring(let tournamentID, let matchID):
                                WatchScoringView(tournamentID: tournamentID, matchID: matchID, path: $path)
                            case .courts(let tournamentID):
                                WatchCourtsView(tournamentID: tournamentID, path: $path)
                            case .standings(let tournamentID):
                                WatchStandingsView(tournamentID: tournamentID)
                            }
                        }
                }
            }
        }
        .onChange(of: router.openActiveMatchRequest) { _, _ in
            openActiveMatch()
        }
        .onChange(of: router.requestedPath) { _, requested in
            guard let requested else { return }
            path = requested
            router.requestedPath = nil
        }
        .onChange(of: store.state) { _, _ in model.publishComplication() }
        .onChange(of: model.selectedMatchID) { _, _ in model.publishComplication() }
        .onAppear { model.publishComplication() }
    }

    private func openActiveMatch() {
        guard let tournament = model.tournament, let match = model.activeMatch(in: tournament) else { return }
        model.selectedMatchID = match.id
        path = [.scoring(tournament.id, match.id)]
    }
}
