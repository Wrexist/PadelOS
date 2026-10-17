import Foundation
import PadelCore
import PadelSync

/// Simulator-only demo data so every watch screen can be inspected and screenshotted
/// without a paired iPhone (used by CI). Launch with `-demo-scoring` (the classic scoring
/// screen) or `-demo-scenario <name>`. Never triggered in normal use.
enum WatchDemo {
    enum Scenario: String, CaseIterable {
        /// Points match in progress, two unsent points on the watch.
        case points
        /// Games and sets with advantage, 40–40.
        case deuce
        /// Golden point, 40–40.
        case golden
        /// 5–3, 40–0: match point.
        case matchpoint
        /// 6–6 tie-break.
        case tiebreak
        /// Total reached, waiting for "Finish".
        case won
        /// Match finished: the celebration screen.
        case finished
        /// Home with live courts.
        case home
        /// Standings after three rounds.
        case standings
        /// Tournament finished: podium on Home.
        case podium
        /// Scoring screen as drawn in Always On.
        case alwayson
        /// Every complication family.
        case complications
        /// App Store screenshots: the iPhone screenshot demo's live match (12 players,
        /// 3 courts, round 3), on the scoring screen, Home or the standings.
        case store
        case storeHome = "store-home"
        case storeStandings = "store-standings"
    }

    static var requestedScenario: Scenario? {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-demo-scenario"), index + 1 < arguments.count {
            return Scenario(rawValue: arguments[index + 1])
        }
        return arguments.contains("-demo-scoring") ? .points : nil
    }

    /// Always On preview (the simulator cannot lower the wrist).
    static var forcesLuminanceReduced: Bool { requestedScenario == .alwayson }
    static var showsComplicationGallery: Bool { requestedScenario == .complications }

    private static let names = ["Alex", "Johan", "Lisa", "Maja", "Erik", "Sofia", "Daniel", "Fredrik"]

    @MainActor
    static func load(_ scenario: Scenario, into model: WatchModel) {
        if [Scenario.store, .storeHome, .storeStandings].contains(scenario) {
            loadStore(scenario, into: model)
            return
        }
        let scoring: ScoringRule
        switch scenario {
        case .deuce: scoring = .sets(.bestOfThree)
        case .golden, .matchpoint, .tiebreak: scoring = .sets(.oneSet)
        default: scoring = .totalPoints(24)
        }
        let draft = TournamentDraft(
            name: "Friday Padel",
            configuration: TournamentConfiguration(format: .americano, courtCount: 2, roundCount: 6, scoring: scoring, seed: 7),
            players: names.map { Player(name: $0) }
        )
        let context = EngineContext(now: Date(), deviceID: DeviceID())
        guard var tournament = try? Tournament.create(from: draft, context: context) else { return }

        func play(_ sides: [TeamSide], in matchID: MatchID) {
            for side in sides { _ = try? tournament.recordPoint(for: side, in: matchID, context: context) }
        }
        func games(_ sides: [TeamSide], in matchID: MatchID) {
            for side in sides { play(Array(repeating: side, count: 4), in: matchID) }
        }
        func completeRound(_ index: Int) {
            guard tournament.rounds.indices.contains(index) else { return }
            for (offset, match) in tournament.rounds[index].matches.enumerated() where !match.isCompleted {
                let a = 8 + (index * 5 + offset * 7) % 9
                _ = try? tournament.enterResult(Score(a: a + 2, b: 22 - a), for: match.id, context: context)
            }
        }

        var focus: MatchID?
        var watchPoints: [TeamSide] = []
        switch scenario {
        case .points, .home, .alwayson:
            guard let first = tournament.rounds.first?.matches.first else { return }
            play([.a, .a, .b, .a, .a, .b, .a, .a, .b, .a, .b, .a, .a, .b, .a, .b, .b, .a], in: first.id)
            if let second = tournament.rounds.first?.matches.dropFirst().first {
                play([.b, .a, .b, .b, .a, .b, .a, .b, .b], in: second.id)
            }
            focus = first.id
            watchPoints = [.b, .b]
        case .deuce:
            guard let first = tournament.rounds.first?.matches.first else { return }
            games([.a, .b, .a], in: first.id)
            play([.a, .b, .a, .b, .a, .b], in: first.id)
            focus = first.id
        case .golden:
            guard let first = tournament.rounds.first?.matches.first else { return }
            games([.a, .b, .a, .b, .a, .a, .b], in: first.id)
            play([.b, .a, .a, .b, .b, .a], in: first.id)
            focus = first.id
        case .matchpoint:
            guard let first = tournament.rounds.first?.matches.first else { return }
            games([.a, .b, .a, .a, .b, .a, .b, .a], in: first.id)
            play([.a, .a, .a], in: first.id)
            focus = first.id
        case .tiebreak:
            guard let first = tournament.rounds.first?.matches.first else { return }
            games([.a, .b, .a, .b, .a, .b, .a, .b, .a, .b, .a, .b], in: first.id)
            play([.a, .b, .a, .a, .b, .b, .a], in: first.id)
            focus = first.id
        case .won, .finished:
            guard let first = tournament.rounds.first?.matches.first else { return }
            play([.a, .b, .a, .a, .b, .a, .b, .a, .a, .b, .a, .b, .a, .a, .b, .a, .b, .b, .a, .a, .b, .a, .b, .a], in: first.id)
            if scenario == .finished { _ = try? tournament.finishMatch(first.id, context: context) }
            focus = first.id
        case .standings:
            for index in 0..<3 { completeRound(index) }
            focus = tournament.currentRound?.matches.first?.id
        case .podium:
            for index in 0..<tournament.rounds.count { completeRound(index) }
            tournament.finish(now: Date())
        case .complications, .store, .storeHome, .storeStandings:
            break
        }

        let snapshot = WatchSnapshot(phoneInstanceID: UUID(), sequence: Int.max / 2, generatedAt: Date(), tournaments: [tournament], acknowledgedEventIDs: [])
        model.store.receive(.snapshot(snapshot))
        if let focus {
            model.selectedMatchID = focus
            // Points recorded on the watch itself stay in the outbox: the sync chip shows them.
            for side in watchPoints { model.store.recordPoint(side, match: focus, tournament: tournament.id) }
        }

        switch scenario {
        case .points, .deuce, .golden, .matchpoint, .tiebreak, .won, .finished, .alwayson:
            if let focus { WatchRouter.shared.requestedPath = [.scoring(tournament.id, focus)] }
        case .standings:
            WatchRouter.shared.requestedPath = [.standings(tournament.id)]
        case .home, .podium, .complications, .store, .storeHome, .storeStandings:
            break
        }
    }

    /// Same players, seed and scores as the iPhone's App Store demo (`AppModel.seedStoreDemo`),
    /// so the watch and the phone show the same match. `-demoLiveName` names it.
    @MainActor
    private static func loadStore(_ scenario: Scenario, into model: WatchModel) {
        let players = ["Carlos", "Lucía", "Marco", "Emma", "Diego", "Sofia", "Lucas", "Nora", "Pablo", "Ana", "Johan", "Maja"]
        let arguments = ProcessInfo.processInfo.arguments
        let name = arguments.firstIndex(of: "-demoLiveName").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let draft = TournamentDraft(
            name: name ?? "Thursday Padel",
            configuration: TournamentConfiguration(format: .americano, courtCount: 3, roundCount: 7, scoring: .totalPoints(24), seed: 7),
            players: players.map { Player(name: $0) }
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
        guard let round = tournament.currentRound, let focus = round.matches.first else { return }
        for (match, score) in zip(round.matches, [(14, 9), (11, 12), (7, 5)]) {
            for _ in 0..<score.0 { _ = try? tournament.recordPoint(for: .a, in: match.id, context: context) }
            for _ in 0..<score.1 { _ = try? tournament.recordPoint(for: .b, in: match.id, context: context) }
        }
        let snapshot = WatchSnapshot(phoneInstanceID: UUID(), sequence: Int.max / 2, generatedAt: Date(), tournaments: [tournament], acknowledgedEventIDs: [])
        model.store.receive(.snapshot(snapshot))
        model.selectedMatchID = focus.id
        switch scenario {
        case .store: WatchRouter.shared.requestedPath = [.scoring(tournament.id, focus.id)]
        case .storeStandings: WatchRouter.shared.requestedPath = [.standings(tournament.id)]
        default: break
        }
    }
}
