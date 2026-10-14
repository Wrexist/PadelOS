import SwiftUI
import WatchKit
import PadelCore
import PadelStore
import PadelSync

@main
struct PadelWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .environment(model.store)
                .environment(WatchRouter.shared)
                .tint(Theme.Colors.accent)
                .task { model.start() }
        }
    }
}

/// Owns the watch store and the WatchConnectivity transport.
@MainActor
@Observable
final class WatchModel {
    let store: WatchStore
    @ObservationIgnored private let transport: WatchConnectivityTransport

    init() {
        transport = WatchConnectivityTransport()
        store = WatchStore(file: WatchStore.defaultFile(), transport: transport)
        selectedMatchID = UserDefaults.standard.string(forKey: Self.selectedMatchKey).flatMap { MatchID(uuidString: $0) }
    }

    func start() {
        store.start()
        if ProcessInfo.processInfo.arguments.contains("-demo-scoring") { loadDemo() }
    }

    /// Simulator-only demo data so the scoring screen can be inspected and screenshotted
    /// without a paired iPhone (used by CI). Never triggered in normal use.
    private func loadDemo() {
        let names = ["Alex", "Johan", "Lisa", "Maja", "Erik", "Sofia", "Daniel", "Fredrik"]
        let draft = TournamentDraft(
            name: "Friday Padel",
            configuration: TournamentConfiguration(format: .americano, courtCount: 2, roundCount: 6, scoring: .totalPoints(24), seed: 7),
            players: names.map { Player(name: $0) }
        )
        let context = EngineContext(now: Date(), deviceID: DeviceID())
        guard var tournament = try? Tournament.create(from: draft, context: context),
              let match = tournament.rounds.first?.matches.first else { return }
        for side in [TeamSide.a, .a, .b, .a, .a, .b, .a, .a, .b, .a, .b, .a, .a, .b, .a, .b, .b, .a, .b, .b] {
            _ = try? tournament.recordPoint(for: side, in: match.id, context: context)
        }
        let snapshot = WatchSnapshot(phoneInstanceID: UUID(), sequence: Int.max / 2, generatedAt: Date(), tournaments: [tournament], acknowledgedEventIDs: [])
        store.receive(.snapshot(snapshot))
        selectedMatchID = match.id
        WatchRouter.shared.openActiveMatchRequest += 1
    }

    // MARK: Selection

    /// The match the wearer last scored, remembered across launches.
    var selectedMatchID: MatchID? {
        didSet { UserDefaults.standard.set(selectedMatchID?.rawValue.uuidString, forKey: Self.selectedMatchKey) }
    }

    private static let selectedMatchKey = "selectedMatchID"

    /// Most relevant tournament: the one containing the selected match, else the most recent.
    var tournament: Tournament? {
        let tournaments = store.tournaments
        if let selected = selectedMatchID, let owner = tournaments.first(where: { $0.match(selected) != nil }) {
            return owner
        }
        return tournaments.first
    }

    /// The match to show on "Active Match": the remembered one while unfinished, otherwise
    /// a live match in the current round, otherwise the first unplayed one.
    func activeMatch(in tournament: Tournament) -> Match? {
        if let selected = selectedMatchID, let match = tournament.match(selected), !match.isCompleted {
            return match
        }
        guard let round = tournament.currentRound else { return nil }
        if let selected = selectedMatchID, let previous = tournament.match(selected),
           let sameCourt = round.matches.first(where: { $0.court == previous.court && !$0.isCompleted }) {
            return sameCourt
        }
        return round.matches.first { $0.status == .inProgress } ?? round.matches.first { !$0.isCompleted }
    }
}

/// Navigation requests from outside the view hierarchy (App Intents).
@MainActor
@Observable
final class WatchRouter {
    static let shared = WatchRouter()
    var openActiveMatchRequest = 0
}

enum WatchHaptics {
    static func point() { WKInterfaceDevice.current().play(.click) }
    static func undo() { WKInterfaceDevice.current().play(.directionDown) }
    static func success() { WKInterfaceDevice.current().play(.success) }
    static func failure() { WKInterfaceDevice.current().play(.failure) }
}
