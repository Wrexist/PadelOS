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
                .tint(WatchPalette.lime)
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
        if let stored = UserDefaults.standard.string(forKey: Self.doubleTapKey) {
            let parts = stored.split(separator: ":")
            if parts.count == 2, let id = MatchID(uuidString: String(parts[0])) {
                doubleTap = (match: id, side: parts[1] == "b" ? TeamSide.b : TeamSide.a)
            }
        }
    }

    func start() {
        store.start()
        if let scenario = WatchDemo.requestedScenario {
            WatchDemo.load(scenario, into: self)
        }
    }

    // MARK: Selection

    /// The match the wearer last scored, remembered across launches.
    var selectedMatchID: MatchID? {
        didSet { UserDefaults.standard.set(selectedMatchID?.rawValue.uuidString, forKey: Self.selectedMatchKey) }
    }

    private static let selectedMatchKey = "selectedMatchID"

    // MARK: Double Tap

    /// The side Double Tap scores for in one match (players change sides every match, so
    /// the choice is remembered per match).
    private var doubleTap: (match: MatchID, side: TeamSide)? = nil {
        didSet {
            let value = doubleTap.map { "\($0.match.rawValue.uuidString):\($0.side == .a ? "a" : "b")" }
            UserDefaults.standard.set(value, forKey: Self.doubleTapKey)
        }
    }

    private static let doubleTapKey = "doubleTapSide"

    func doubleTapSide(for match: MatchID) -> TeamSide? {
        guard let doubleTap, doubleTap.match == match else { return nil }
        return doubleTap.side
    }

    func setDoubleTapSide(_ side: TeamSide?, for match: MatchID) {
        doubleTap = side.map { (match: match, side: $0) }
    }

    // MARK: Complication

    /// Writes the active match for the complication and reloads it only when it changed.
    func publishComplication() {
        var snapshot: ActiveMatchSnapshot?
        if let tournament, let match = activeMatch(in: tournament) ?? selectedMatchID.flatMap({ tournament.match($0) }) {
            let rule = tournament.scoringRule(for: match)
            snapshot = ActiveMatchSnapshot(
                tournamentName: tournament.name,
                roundLabel: tournament.shortProgressLabel,
                court: match.court,
                teamA: tournament.sideNames(of: match, .a).joined(separator: "/"),
                teamB: tournament.sideNames(of: match, .b).joined(separator: "/"),
                scoreA: match.score.a,
                scoreB: match.score.b,
                total: rule.totalPoints,
                isFinished: match.isCompleted,
                roundProgress: tournament.progressFraction,
                situation: rule.setsRules.flatMap { (match.sets ?? SetsState()).situation(rules: $0) }
            )
        }
        if ActiveMatchSnapshot.store(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: Queries

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

/// Navigation requests from outside the view hierarchy (App Intents, demo mode).
@MainActor
@Observable
final class WatchRouter {
    static let shared = WatchRouter()
    var openActiveMatchRequest = 0
    /// A full navigation path to show (demo scenarios).
    var requestedPath: [WatchRoute]? = nil
}

enum WatchHaptics {
    static func point() { WKInterfaceDevice.current().play(.click) }
    /// A game, set or the match was won with this point.
    static func milestone() { WKInterfaceDevice.current().play(.success) }
    static func undo() { WKInterfaceDevice.current().play(.directionDown) }
    static func success() { WKInterfaceDevice.current().play(.success) }
    static func failure() { WKInterfaceDevice.current().play(.failure) }
    /// The Digital Crown has been turned far enough to undo.
    static func armed() { WKInterfaceDevice.current().play(.retry) }
}
