import Foundation
@testable import PadelCore

enum Fixtures {
    static let names = ["Alex", "Lisa", "Johan", "Maja", "Erik", "Daniel", "Sofia", "Fredrik",
                        "Anna", "Oscar", "Emma", "Lucas", "Elsa", "Hugo", "Wilma", "Liam",
                        "Alva", "Noah", "Ella", "Adam", "Ebba", "Leo", "Saga", "Nils",
                        "Vera", "Axel", "Iris", "Theo", "Stella", "Otto", "Ines", "Max",
                        "Mira", "Arvid", "Lova", "Sixten", "Juni", "Melker", "Tyra", "Ivar"]

    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func context(seed: UInt64 = 7, device: DeviceID = DeviceID(UUID(uuidString: "00000000-0000-4000-8000-000000000001")!)) -> EngineContext {
        EngineContext(now: start, deviceID: device, ids: SequentialIdentifierGenerator(seed: seed))
    }

    static func players(_ count: Int, ids: IdentifierGenerating = SequentialIdentifierGenerator(seed: 99)) -> [Player] {
        (0..<count).map { i in
            let name = i < names.count ? names[i] : "Player \(i + 1)"
            return Player(id: PlayerID(ids.next()), name: name)
        }
    }

    static func mixedPlayers(a: Int, b: Int) -> [Player] {
        let ids = SequentialIdentifierGenerator(seed: 98)
        var result: [Player] = []
        for i in 0..<a { result.append(Player(id: PlayerID(ids.next()), name: "A\(i + 1)", group: .a)) }
        for i in 0..<b { result.append(Player(id: PlayerID(ids.next()), name: "B\(i + 1)", group: .b)) }
        return result
    }

    static func teams(_ count: Int) -> (players: [Player], teams: [Team]) {
        let ids = SequentialIdentifierGenerator(seed: 97)
        let players = (0..<(count * 2)).map { Player(id: PlayerID(ids.next()), name: "P\($0 + 1)") }
        let teams = (0..<count).map { t in
            Team(id: TeamID(ids.next()), name: "Team \(t + 1)", playerIDs: [players[2 * t].id, players[2 * t + 1].id])
        }
        return (players, teams)
    }

    static func tournament(
        format: TournamentFormat = .americano,
        players playerCount: Int = 8,
        courts: Int = 2,
        rounds: Int = 7,
        points: Int = 24,
        seed: UInt64 = 1,
        finalRound: Bool = false,
        restCompensation: RestCompensation = .none
    ) throws -> Tournament {
        let config = TournamentConfiguration(format: format, courtCount: courts, roundCount: rounds, scoring: .totalPoints(points), standingsBasedFinalRound: finalRound, restCompensation: restCompensation, seed: seed)
        let draft: TournamentDraft
        switch format {
        case .teamAmericano:
            let fixture = teams(playerCount)
            draft = TournamentDraft(name: "Test", configuration: config, players: fixture.players, teams: fixture.teams)
        case .mixedAmericano:
            draft = TournamentDraft(name: "Test", configuration: config, players: mixedPlayers(a: playerCount / 2, b: playerCount - playerCount / 2))
        default:
            draft = TournamentDraft(name: "Test", configuration: config, players: players(playerCount))
        }
        return try Tournament.create(from: draft, context: context(seed: seed))
    }

    /// Plays a match to a final score through the public scoring API.
    static func play(_ tournament: inout Tournament, _ matchID: MatchID, a: Int, b: Int, context: EngineContext) throws {
        for _ in 0..<a { try tournament.recordPoint(for: .a, in: matchID, context: context) }
        for _ in 0..<b { try tournament.recordPoint(for: .b, in: matchID, context: context) }
        try tournament.finishMatch(matchID, context: context)
    }

    /// Completes the current round with deterministic pseudo-random results.
    static func completeCurrentRound(_ tournament: inout Tournament, random: inout SeededGenerator, context: EngineContext) throws {
        guard let round = tournament.currentRound else { return }
        let total = tournament.configuration.scoring.totalPoints ?? 20
        for match in round.matches where !match.isCompleted {
            let a = random.nextInt(total + 1)
            try tournament.enterResult(Score(a: a, b: total - a), for: match.id, context: context)
        }
    }
}

/// Structural invariants every generated round must satisfy.
enum Invariants {
    static func check(_ tournament: Tournament) -> [String] {
        var problems: [String] = []
        let format = tournament.configuration.format
        for round in tournament.rounds {
            var seen = Set<PlayerID>()
            // Started rounds keep their courts even if the court count is lowered later.
            if !round.hasStarted && round.matches.count > tournament.configuration.courtCount {
                problems.append("Round \(round.number) uses \(round.matches.count) courts")
            }
            for match in round.matches {
                for side in [match.sideA, match.sideB] {
                    if side.playerIDs.count != 2 { problems.append("Round \(round.number) side with \(side.playerIDs.count) players") }
                    if format == .mixedAmericano {
                        let groups = side.playerIDs.compactMap { tournament.player($0)?.group }
                        if Set(groups) != [.a, .b] { problems.append("Round \(round.number) mixed team is not one of each group") }
                    }
                    if format == .teamAmericano {
                        guard let teamID = side.teamID, let team = tournament.team(teamID) else {
                            problems.append("Round \(round.number) side without team"); continue
                        }
                        if Set(team.playerIDs) != Set(side.playerIDs) { problems.append("Round \(round.number) team players mismatch") }
                    }
                }
                for player in match.allPlayerIDs {
                    if seen.contains(player) { problems.append("Round \(round.number): \(tournament.playerName(player)) assigned twice") }
                    seen.insert(player)
                }
            }
            for player in round.restingPlayerIDs where seen.contains(player) {
                problems.append("Round \(round.number): \(tournament.playerName(player)) both plays and rests")
            }
            // Every active participant is either playing or resting in rounds not yet started.
            if !round.hasStarted && format.isIndividual {
                let accounted = seen.union(round.restingPlayerIDs)
                for player in tournament.activePlayers where !accounted.contains(player.id) {
                    problems.append("Round \(round.number): \(player.name) neither plays nor rests")
                }
                for player in accounted where tournament.withdrawnPlayerIDs.contains(player) {
                    problems.append("Round \(round.number): withdrawn \(tournament.playerName(player)) scheduled")
                }
            }
        }
        return problems
    }
}
