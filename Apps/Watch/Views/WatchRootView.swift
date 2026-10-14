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
        .onChange(of: router.openActiveMatchRequest) { _, _ in
            openActiveMatch()
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

struct WatchHomeView: View {
    @Environment(WatchModel.self) private var model
    @Environment(WatchStore.self) private var store
    @Binding var path: [WatchRoute]

    var body: some View {
        List {
            if let tournament = model.tournament {
                Section {
                    if let match = model.activeMatch(in: tournament) {
                        Button {
                            model.selectedMatchID = match.id
                            path.append(.scoring(tournament.id, match.id))
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "play.fill")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.Colors.onAccent)
                                    .frame(width: 30, height: 30)
                                    .background(Theme.Colors.accent, in: Circle())
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(match.hasStarted ? "Active Match" : "Start Match")
                                        .font(.headline)
                                        .foregroundStyle(Theme.Colors.accent)
                                    Text("Court \(match.court) · \(match.score.a)–\(match.score.b)")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("watchActiveMatch")
                    } else if tournament.allRoundsCompleted || tournament.status == .completed {
                        Label("All rounds played", systemImage: "flag.checkered")
                            .font(.footnote)
                    } else {
                        Label("Waiting for iPhone to draw the next round", systemImage: "iphone")
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    NavigationLink(value: WatchRoute.courts(tournament.id)) {
                        Label("Courts", systemImage: "square.grid.2x2")
                    }
                    NavigationLink(value: WatchRoute.standings(tournament.id)) {
                        Label("Standings", systemImage: "list.number")
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tournament.name).lineLimit(1)
                        Text(tournament.progressLabel).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .textCase(nil)
                }

                if store.tournaments.count > 1 {
                    Section("Other tournaments") {
                        ForEach(store.tournaments.filter { $0.id != tournament.id }) { other in
                            Button(other.name) {
                                if let match = model.activeMatch(in: other) ?? other.currentRound?.matches.first {
                                    model.selectedMatchID = match.id
                                }
                            }
                        }
                    }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "iphone.gen3")
                            .font(.title3)
                            .foregroundStyle(Theme.Colors.accent)
                        Text("Create a tournament on your iPhone")
                            .font(.headline)
                        Text("It appears here automatically. Then you can score without your phone.")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                WatchSyncStatusRow()
            }
        }
        .navigationTitle("Padel")
    }
}

struct WatchSyncStatusRow: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.footnote)
                if let detail {
                    Text(detail).font(.caption2).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch store.syncStatus {
        case .waitingForPhone: "iphone.slash"
        case .upToDate: "checkmark.circle"
        case .pending(_, let reachable): reachable ? "arrow.triangle.2.circlepath" : "tray.full"
        }
    }

    private var tint: Color {
        switch store.syncStatus {
        case .upToDate: Theme.Colors.accent
        case .waitingForPhone: Theme.Colors.textSecondary
        case .pending: Theme.Colors.warning
        }
    }

    private var title: String {
        switch store.syncStatus {
        case .waitingForPhone: String(localized: "Not synced yet")
        case .upToDate: String(localized: "Saved on iPhone")
        case .pending(let count, _): String(localized: "\(count) changes on watch")
        }
    }

    private var detail: String? {
        switch store.syncStatus {
        case .waitingForPhone: String(localized: "Open PadelOS on iPhone")
        case .upToDate: nil
        case .pending(_, let reachable): reachable ? String(localized: "Sending…") : String(localized: "Sent when iPhone is nearby")
        }
    }
}

struct WatchCourtsView: View {
    @Environment(WatchModel.self) private var model
    @Environment(WatchStore.self) private var store
    let tournamentID: TournamentID
    @Binding var path: [WatchRoute]

    var body: some View {
        List {
            if let tournament = store.state.tournament(tournamentID) {
                let rounds = tournament.rounds.filter { !$0.isCompleted }.prefix(2)
                ForEach(Array(rounds)) { round in
                    Section(tournament.roundTitle(round)) {
                        ForEach(round.matches) { match in
                            Button {
                                model.selectedMatchID = match.id
                                path.append(.scoring(tournamentID, match.id))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("Court \(match.court)").font(.headline)
                                        Spacer()
                                        if match.hasStarted {
                                            Text("\(match.score.a)–\(match.score.b)")
                                                .font(.headline.monospacedDigit())
                                                .foregroundStyle(match.isCompleted ? Theme.Colors.textSecondary : Theme.Colors.accent)
                                        }
                                    }
                                    Text(tournament.sideNames(of: match, .a).joined(separator: " / "))
                                        .font(.caption2).lineLimit(1)
                                    Text(tournament.sideNames(of: match, .b).joined(separator: " / "))
                                        .font(.caption2).lineLimit(1)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                            .accessibilityLabel(tournament.accessibilityDescription(of: match))
                        }
                    }
                }
                if rounds.isEmpty {
                    Text("No matches left to play.")
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Courts")
    }
}

struct WatchStandingsView: View {
    @Environment(WatchStore.self) private var store
    let tournamentID: TournamentID

    var body: some View {
        List {
            if let tournament = store.state.tournament(tournamentID) {
                let standings = StandingsCalculator.compute(tournament)
                ForEach(standings.entries) { entry in
                    HStack {
                        Text(entry.isTied ? "=\(entry.rank)" : "\(entry.rank)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(entry.rank == 1 ? Theme.Colors.accent : Theme.Colors.textSecondary)
                            .frame(width: 26, alignment: .leading)
                        Text(entry.name).lineLimit(1)
                        Spacer()
                        Text("\(entry.points)").font(.body.monospacedDigit().weight(.semibold))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Standings")
    }
}
