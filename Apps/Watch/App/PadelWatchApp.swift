import SwiftUI
import WatchKit
import WidgetKit
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

    /// Simulator-only demo data so the watch screens can be inspected and screenshotted
    /// without a paired iPhone (used by CI). Never triggered in normal use. Mirrors the
    /// iPhone's App Store demo (same players, seed and scores), so both show the same
    /// match. `-demoScreen home|courts|standings` opens another screen instead of scoring;
    /// `-demoLiveName` sets the tournament name.
    private func loadDemo() {
        let names = ["Carlos", "Lucía", "Marco", "Emma", "Diego", "Sofia", "Lucas", "Nora", "Pablo", "Ana", "Johan", "Maja"]
        let defaults = UserDefaults.standard
        let draft = TournamentDraft(
            name: defaults.string(forKey: "demoLiveName") ?? "Thursday Padel",
            configuration: TournamentConfiguration(format: .americano, courtCount: 3, roundCount: 7, scoring: .totalPoints(24), seed: 7),
            players: names.map { Player(name: $0) }
        )
        let context = EngineContext(now: Date(), deviceID: DeviceID())
        guard var tournament = try? Tournament.create(from: draft, context: context) else { return }
        var results = [Score(a: 15, b: 9), Score(a: 11, b: 13), Score(a: 14, b: 10), Score(a: 12, b: 12), Score(a: 9, b: 15), Score(a: 16, b: 8)].makeIterator()
        for _ in 0..<2 {
            guard let round = tournament.currentRound else { break }
            for match in round.matches {
                try? tournament.enterResult(results.next() ?? Score(a: 13, b: 11), for: match.id, context: context)
            }
        }
        guard let round = tournament.currentRound, let match = round.matches.first else { return }
        for (current, score) in zip(round.matches, [(14, 9), (11, 12), (7, 5)]) {
            for _ in 0..<score.0 { _ = try? tournament.recordPoint(for: .a, in: current.id, context: context) }
            for _ in 0..<score.1 { _ = try? tournament.recordPoint(for: .b, in: current.id, context: context) }
        }
        let snapshot = WatchSnapshot(phoneInstanceID: UUID(), sequence: Int.max / 2, generatedAt: Date(), tournaments: [tournament], acknowledgedEventIDs: [])
        store.receive(.snapshot(snapshot))
        selectedMatchID = match.id
        switch defaults.string(forKey: "demoScreen") {
        case "home": break
        case "courts": WatchRouter.shared.demoPath = [.courts(tournament.id)]
        case "standings": WatchRouter.shared.demoPath = [.standings(tournament.id)]
        default: WatchRouter.shared.openActiveMatchRequest += 1
        }
    }

    // MARK: Selection

    /// The match the wearer last scored, remembered across launches.
    var selectedMatchID: MatchID? {
        didSet { UserDefaults.standard.set(selectedMatchID?.rawValue.uuidString, forKey: Self.selectedMatchKey) }
    }

    private static let selectedMatchKey = "selectedMatchID"

    /// Writes the active match for the complication and reloads it only when it changed.
    func publishComplication() {
        var snapshot: ActiveMatchSnapshot?
        if let tournament, let match = activeMatch(in: tournament) ?? selectedMatchID.flatMap({ tournament.match($0) }) {
            snapshot = ActiveMatchSnapshot(
                tournamentName: tournament.name,
                roundLabel: tournament.shortProgressLabel,
                court: match.court,
                teamA: tournament.sideNames(of: match, .a).joined(separator: "/"),
                teamB: tournament.sideNames(of: match, .b).joined(separator: "/"),
                scoreA: match.score.a,
                scoreB: match.score.b,
                total: tournament.scoringRule(for: match).totalPoints,
                isFinished: match.isCompleted
            )
        }
        if ActiveMatchSnapshot.store(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

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
    /// Simulator demo only (`-demo-scoring -demoScreen …`): a screen to open.
    var demoPath: [WatchRoute]?
}

enum WatchHaptics {
    static func point() { WKInterfaceDevice.current().play(.click) }
    static func undo() { WKInterfaceDevice.current().play(.directionDown) }
    static func success() { WKInterfaceDevice.current().play(.success) }
    static func failure() { WKInterfaceDevice.current().play(.failure) }
}
