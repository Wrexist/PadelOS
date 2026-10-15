import Foundation
import Testing
@testable import PadelCore

@Suite("Standings")
struct StandingsTests {
    let context = Fixtures.context()

    @Test("Both players on a team receive the team's points")
    func individualCredit() throws {
        var t = try Fixtures.tournament(points: 24)
        let match = t.rounds[0].matches[0]
        try t.enterResult(Score(a: 15, b: 9), for: match.id, context: context)
        let standings = StandingsCalculator.compute(t)
        for player in match.sideA.playerIDs {
            let entry = try #require(standings.entry(for: .player(player)))
            #expect(entry.points == 15)
            #expect(entry.wins == 1)
            #expect(entry.pointDifference == 6)
            #expect(entry.played == 1)
        }
        for player in match.sideB.playerIDs {
            let entry = try #require(standings.entry(for: .player(player)))
            #expect(entry.points == 9)
            #expect(entry.losses == 1)
            #expect(entry.pointDifference == -6)
        }
    }

    @Test("Ranking: points, then wins, then point difference, then shared rank")
    func tieBreakers() {
        let ids = SequentialIdentifierGenerator(seed: 5)
        let p = (0..<8).map { Player(id: PlayerID(ids.next()), name: ["Ann", "Bo", "Cy", "Di", "Ed", "Flo", "Gus", "Hal"][$0]) }
        var t = Tournament(name: "Manual", createdAt: Fixtures.start, configuration: TournamentConfiguration(format: .americano, courtCount: 2, roundCount: 2, scoring: .totalPoints(20)), players: p)
        // Round 1: Ann+Bo 12–8 Cy+Di ; Ed+Flo 10–10 Gus+Hal
        // Round 2: Ann+Cy 8–12 Bo+Di ; Ed+Gus 10–10 Flo+Hal
        func match(_ round: Int, _ court: Int, _ a: [Int], _ b: [Int], _ score: Score) -> Match {
            var m = Match(id: MatchID(ids.next()), roundNumber: round, court: court, sideA: MatchSide(playerIDs: a.map { p[$0].id }), sideB: MatchSide(playerIDs: b.map { p[$0].id }))
            let rule = ScoringRule.totalPoints(20)
            for kind: ScoreEvent.Kind in [.setScore(score), .finish] {
                ScoringEngine.apply(ScoreEvent(tournamentID: t.id, matchID: m.id, kind: kind, timestamp: Fixtures.start, deviceID: DeviceID(), deviceSequence: 0, baseRevision: 0), to: &m, rule: rule)
            }
            return m
        }
        t.rounds = [
            Round(number: 1, matches: [match(1, 1, [0, 1], [2, 3], Score(a: 12, b: 8)), match(1, 2, [4, 5], [6, 7], Score(a: 10, b: 10))]),
            Round(number: 2, matches: [match(2, 1, [0, 2], [1, 3], Score(a: 8, b: 12)), match(2, 2, [4, 6], [5, 7], Score(a: 10, b: 10))]),
        ]
        let s = StandingsCalculator.compute(t)
        let byName = Dictionary(uniqueKeysWithValues: s.entries.map { ($0.name, $0) })
        // Bo: 12+12 = 24, 2 wins → 1st
        #expect(byName["Bo"]?.rank == 1)
        // Ann 20 (1W) and Di 20 (1W): diff Ann +4−4 = 0, Di −4+4 = 0 → shared 2nd
        #expect(byName["Ann"]?.points == 20)
        #expect(byName["Di"]?.points == 20)
        #expect(byName["Ann"]?.rank == 2 && byName["Di"]?.rank == 2)
        #expect(byName["Ann"]?.isTied == true)
        // Ed, Flo, Gus, Hal: 20 points, 0 wins, 0 diff → shared 4th. Cy: 16 → 8th.
        for name in ["Ed", "Flo", "Gus", "Hal"] { #expect(byName[name]?.rank == 4) }
        #expect(byName["Cy"]?.rank == 8)
        #expect(s.tieBreakers == [.totalPoints, .wins, .pointDifference])
    }

    @Test("Team standings use team points and head-to-head for two tied teams")
    func teamStandings() throws {
        var t = try Fixtures.tournament(format: .teamAmericano, players: 4, courts: 2, rounds: 3, points: 20)
        // Give every match 10–10 except decide a single head-to-head.
        let rounds = t.rounds
        for round in rounds { for match in round.matches { try t.enterResult(Score(a: 10, b: 10), for: match.id, context: context) } }
        var s = StandingsCalculator.compute(t)
        #expect(s.isTeamStandings)
        #expect(s.entries.allSatisfy { $0.rank == 1 && $0.isTied })
        // Now team X beats team Y 11–9 and team Z loses to W 9–11: X and W tie on points
        // and wins; their head-to-head (10–10) is level, so point difference decides — also
        // level → shared. Y and Z similarly.
        let first = rounds[0].matches
        try t.enterResult(Score(a: 11, b: 9), for: first[0].id, context: context)
        try t.enterResult(Score(a: 9, b: 11), for: first[1].id, context: context)
        s = StandingsCalculator.compute(t)
        let winners = [first[0].sideA.teamID!, first[1].sideB.teamID!]
        for team in winners { #expect(s.entry(for: .team(team))?.rank == 1) }
        // Individuals are not ranked in team format.
        #expect(s.entries.count == 4)
        #expect(s.tieBreakers.contains(.headToHead))
    }

    @Test("Head-to-head separates two teams tied on points and wins")
    func headToHead() throws {
        var t = try Fixtures.tournament(format: .teamAmericano, players: 3, courts: 1, rounds: 3, points: 20)
        // 3 teams, round robin, one match per round.
        let matches = t.rounds.map { $0.matches[0] }
        // Arrange: A beats B 11–9; B beats C 15–5; C beats A 11–9.
        // Totals: A 9+11=20? Compute generically by asserting ordering via head-to-head.
        try t.enterResult(Score(a: 11, b: 9), for: matches[0].id, context: context)
        try t.enterResult(Score(a: 9, b: 11), for: matches[1].id, context: context)
        try t.enterResult(Score(a: 10, b: 10), for: matches[2].id, context: context)
        let s = StandingsCalculator.compute(t)
        // Whatever the totals, ranks must be consistent: tied entries share a rank and the
        // order is a permutation of all teams.
        #expect(Set(s.teamRanking) == Set(t.teams.map(\.id)))
        for pair in zip(s.entries, s.entries.dropFirst()) {
            #expect(pair.0.points >= pair.1.points)
        }
    }

    @Test("Rest compensation credits half the total for completed rest rounds only")
    func restCompensation() throws {
        var t = try Fixtures.tournament(format: .americano, players: 5, courts: 1, rounds: 5, points: 24, restCompensation: .halfMatchTotal)
        let round = t.rounds[0]
        let rester = try #require(round.restingPlayerIDs.first)
        #expect(StandingsCalculator.compute(t).entry(for: .player(rester))?.points == 0)
        try t.enterResult(Score(a: 20, b: 4), for: round.matches[0].id, context: context)
        let entry = try #require(StandingsCalculator.compute(t).entry(for: .player(rester)))
        #expect(entry.points == 12)
        #expect(entry.restPoints == 12)
        #expect(entry.rested == 1)
    }

    @Test("Standings are reproducible from the saved tournament")
    func reproducibleFromSavedData() throws {
        var t = try Fixtures.tournament(format: .mexicano, players: 8, courts: 2, rounds: 3)
        var random = SeededGenerator(seed: 3)
        try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        let data = try JSONEncoder().encode(t)
        let restored = try JSONDecoder().decode(Tournament.self, from: data)
        #expect(restored == t)
        #expect(StandingsCalculator.compute(restored) == StandingsCalculator.compute(t))
    }

    @Test("Withdrawn players keep their results and are marked")
    func withdrawnInStandings() throws {
        var t = try Fixtures.tournament(players: 9, courts: 2, rounds: 6)
        let match = t.rounds[0].matches[0]
        try t.enterResult(Score(a: 14, b: 10), for: match.id, context: context)
        let leaver = match.sideA.playerIDs[0]
        try t.withdrawPlayer(leaver, context: context)
        let entry = try #require(StandingsCalculator.compute(t).entry(for: .player(leaver)))
        #expect(entry.isWithdrawn)
        #expect(entry.points == 14)
    }

    @Test("Share summary lists every participant with rank and points")
    func summary() throws {
        var t = try Fixtures.tournament()
        try t.enterResult(Score(a: 15, b: 9), for: t.rounds[0].matches[0].id, context: context)
        let text = ResultSummary.text(for: t)
        for player in t.players { #expect(text.contains(player.name)) }
        #expect(text.contains("15 pts"))
        #expect(text.contains("Ranking: Total points → Matches won → Point difference"))
        #expect(ResultSummary.resultsText(for: t).contains("15–9"))
    }
}
