import Foundation
import Testing
@testable import PadelCore

@Suite("Games and sets scoring")
struct SetsScoringTests {
    let context = Fixtures.context()

    func tournament(_ rules: SetsRules, format: TournamentFormat = .americano, players: Int = 4, rounds: Int = 3) throws -> Tournament {
        let config = TournamentConfiguration(format: format, courtCount: 1, roundCount: rounds, scoring: .sets(rules))
        let draft: TournamentDraft
        if format.usesTeams {
            let fixture = Fixtures.teams(players)
            draft = TournamentDraft(name: "Sets", configuration: config, players: fixture.players, teams: fixture.teams)
        } else {
            draft = TournamentDraft(name: "Sets", configuration: config, players: Fixtures.players(players))
        }
        return try Tournament.create(from: draft, context: context)
    }

    /// Plays rallies described by a string of "a"/"b" characters.
    func play(_ rallies: String, _ t: inout Tournament, _ id: MatchID) throws {
        for c in rallies { try t.recordPoint(for: c == "a" ? .a : .b, in: id, context: context) }
    }

    func game(_ side: TeamSide) -> String { String(repeating: side == .a ? "a" : "b", count: 4) }

    @Test("Points count 0, 15, 30, 40 and a fourth point wins the game")
    func gameProgression() throws {
        var t = try tournament(.oneSet)
        let id = t.rounds[0].matches[0].id
        let rules = SetsRules.oneSet
        try play("a", &t, id)
        #expect(t.match(id)?.sets?.pointLabel(.a, rules: rules) == "15")
        try play("ab", &t, id)
        #expect(t.match(id)?.sets?.pointLabel(.a, rules: rules) == "30")
        #expect(t.match(id)?.sets?.pointLabel(.b, rules: rules) == "15")
        try play("a", &t, id)
        #expect(t.match(id)?.sets?.pointLabel(.a, rules: rules) == "40")
        try play("a", &t, id)
        let sets = try #require(t.match(id)?.sets)
        #expect(sets.games == Score(a: 1, b: 0))
        #expect(sets.points == .zero)
        #expect(t.match(id)?.score == Score(a: 1, b: 0), "standings score counts games")
    }

    @Test("Golden point: at 40–40 the next point wins")
    func goldenPoint() throws {
        var t = try tournament(.oneSet)
        let id = t.rounds[0].matches[0].id
        try play("aaabbb", &t, id)
        #expect(t.match(id)?.sets?.situation(rules: .oneSet) == "Golden point")
        try play("b", &t, id)
        #expect(t.match(id)?.sets?.games == Score(a: 0, b: 1))
    }

    @Test("Advantage scoring: deuce, advantage, back to deuce, then two clear points")
    func advantage() throws {
        let rules = SetsRules.bestOfThree
        var t = try tournament(rules)
        let id = t.rounds[0].matches[0].id
        try play("aaabbb", &t, id)
        #expect(t.match(id)?.sets?.situation(rules: rules) == "Deuce")
        try play("a", &t, id)
        #expect(t.match(id)?.sets?.pointLabel(.a, rules: rules) == "Ad")
        #expect(t.match(id)?.sets?.pointLabel(.b, rules: rules) == "40")
        try play("b", &t, id)
        #expect(t.match(id)?.sets?.situation(rules: rules) == "Deuce")
        try play("bb", &t, id)
        #expect(t.match(id)?.sets?.games == Score(a: 0, b: 1))
    }

    @Test("A set is won 6–4, needs two games at 5–5, and goes to a tie-break at 6–6")
    func setsAndTieBreak() throws {
        var t = try tournament(.oneSet)
        let id = t.rounds[0].matches[0].id
        // 5–5
        for _ in 0..<5 { try play(game(.a) + game(.b), &t, id) }
        #expect(t.match(id)?.sets?.games == Score(a: 5, b: 5))
        try play(game(.a), &t, id)
        #expect(t.match(id)?.sets?.games == Score(a: 6, b: 5), "6–5 is not a set")
        try play(game(.b), &t, id)
        #expect(t.match(id)?.sets?.inTieBreak == true)
        // Tie-break to 7 by two: 6–6 in points, then two in a row.
        try play("abababababab", &t, id)
        #expect(t.match(id)?.sets?.points == Score(a: 6, b: 6))
        try play("aa", &t, id)
        let sets = try #require(t.match(id)?.sets)
        #expect(sets.winner == .a)
        #expect(sets.completedSets == [Score(a: 7, b: 6)])
        #expect(sets.summary() == "7-6(6)")
        #expect(t.match(id)?.score == Score(a: 7, b: 6))
        // Decided: further points are refused, finishing is allowed.
        #expect(throws: TournamentError.scoring(.totalReached)) { try t.recordPoint(for: .b, in: id, context: context) }
        #expect(ScoringEngine.isAwaitingConfirmation(t.match(id)!, rule: t.configuration.scoring))
        try t.finishMatch(id, context: context)
        #expect(t.match(id)?.isCompleted == true)
    }

    @Test("A match cannot be finished before it is decided")
    func finishRequiresDecision() throws {
        var t = try tournament(.oneSet)
        let id = t.rounds[0].matches[0].id
        try play(game(.a), &t, id)
        #expect(throws: TournamentError.scoring(.scoreIncomplete)) { try t.finishMatch(id, context: context) }
    }

    @Test("Best of three with a super tie-break decider")
    func superTieBreak() throws {
        let rules = SetsRules.bestOfThreeSuperTieBreak
        var t = try tournament(rules)
        let id = t.rounds[0].matches[0].id
        try play(String(repeating: game(.a), count: 6), &t, id)          // 6–0
        try play(String(repeating: game(.b), count: 6), &t, id)          // 0–6
        let state = try #require(t.match(id)?.sets)
        #expect(state.isSuperTieBreak)
        #expect(state.situation(rules: rules) == "Match tie-break")
        try play(String(repeating: "ab", count: 9), &t, id)              // 9–9
        try play("bb", &t, id)                                           // 9–11
        let final = try #require(t.match(id)?.sets)
        #expect(final.winner == .b)
        #expect(final.summary() == "6-0 0-6 [9-11]")
        #expect(final.totalGames == Score(a: 6, b: 7), "match tie-break counts as one game")
    }

    @Test("Undo across a game boundary restores the previous points and games")
    func undoAcrossGame() throws {
        var t = try tournament(.oneSet)
        let id = t.rounds[0].matches[0].id
        try play("aaab", &t, id)   // 40–15
        try play("a", &t, id)      // game A
        #expect(t.match(id)?.sets?.games == Score(a: 1, b: 0))
        try t.undoLastScoreChange(in: id, context: context)
        let sets = try #require(t.match(id)?.sets)
        #expect(sets.games == .zero)
        #expect(sets.points == Score(a: 3, b: 1))
        #expect(t.match(id)?.score == .zero)
    }

    @Test("Entered set scores are validated against the rules")
    func manualSets() throws {
        var t = try tournament(.bestOfThreeSuperTieBreak)
        let id = t.rounds[0].matches[0].id
        for illegal in [[Score(a: 6, b: 5)], [Score(a: 5, b: 3)], [Score(a: 6, b: 4)], [Score(a: 6, b: 4), Score(a: 6, b: 4), Score(a: 6, b: 4)], [Score(a: 6, b: 4), Score(a: 3, b: 6), Score(a: 6, b: 4)]] {
            #expect(throws: TournamentError.self, "\(illegal)") { try t.enterSetsResult(illegal, for: id, context: context) }
        }
        try t.enterSetsResult([Score(a: 6, b: 4), Score(a: 6, b: 7), Score(a: 10, b: 8)], for: id, context: context)
        let match = try #require(t.match(id))
        #expect(match.isCompleted)
        #expect(match.sets?.winner == .a)
        #expect(match.sets?.summary() == "6-4 6-7 [10-8]")
        #expect(match.score == Score(a: 13, b: 11))
        // Correction keeps the audit trail and updates the winner.
        try t.enterSetsResult([Score(a: 4, b: 6), Score(a: 3, b: 6)], for: id, context: context)
        #expect(t.match(id)?.sets?.winner == .b)
        #expect(throws: TournamentError.self) { try t.enterResult(Score(a: 6, b: 4), for: id, context: context) }
    }

    @Test("Standings: points are games, wins are decided by sets")
    func standings() throws {
        var t = try tournament(.bestOfThree)
        let id = t.rounds[0].matches[0].id
        // A wins 7–5 0–6 7–5: fewer games (14 vs 16) but the match.
        try t.enterSetsResult([Score(a: 7, b: 5), Score(a: 0, b: 6), Score(a: 7, b: 5)], for: id, context: context)
        let match = try #require(t.match(id))
        let standings = StandingsCalculator.compute(t)
        let aPlayer = match.sideA.playerIDs[0], bPlayer = match.sideB.playerIDs[0]
        #expect(standings.entry(for: .player(aPlayer))?.wins == 1)
        #expect(standings.entry(for: .player(aPlayer))?.points == 14)
        #expect(standings.entry(for: .player(bPlayer))?.losses == 1)
        #expect(standings.entry(for: .player(bPlayer))?.points == 16)
    }

    @Test("Replay always equals the incremental state (random rallies, seed 31)")
    func randomisedReplay() throws {
        var random = SeededGenerator(seed: 31)
        for rules in SetsRules.presets {
            var t = try tournament(rules)
            let id = t.rounds[0].matches[0].id
            var steps = 0
            while !(t.match(id)!.sets?.isDecided ?? false) && steps < 2_000 {
                if random.nextInt(8) == 0 {
                    _ = try? t.undoLastScoreChange(in: id, context: context)
                } else {
                    try t.recordPoint(for: random.nextInt(2) == 0 ? .a : .b, in: id, context: context)
                }
                let match = t.match(id)!
                let replay = ScoringEngine.replay(match.log, rule: t.configuration.scoring)
                #expect(replay.sets == match.sets)
                #expect(replay.score == match.score)
                steps += 1
            }
            let final = try #require(t.match(id)?.sets)
            #expect(final.isDecided, "\(rules.displayName)")
            #expect(final.setsWon[final.winner!] == rules.setsToWin)
            // Every completed set is a legal score.
            for (index, set) in final.completedSets.enumerated() {
                #expect(rules.isLegalSetScore(set, isSuperTieBreak: index == final.superTieBreakSet), "\(set)")
            }
            // And the entered-result path accepts the same sets.
            #expect(SetsState.fromFinalSets(final.completedSets, rules: rules)?.winner == final.winner)
        }
    }

    @Test("Short sets to four with golden point")
    func shortSet() throws {
        var t = try tournament(.shortSet)
        let id = t.rounds[0].matches[0].id
        try play(String(repeating: game(.a), count: 4), &t, id)
        #expect(t.match(id)?.sets?.winner == .a)
        #expect(t.match(id)?.sets?.summary() == "4-0")
    }

    @Test("Games and sets work with fixed teams and survive encoding")
    func teamsAndCodable() throws {
        var t = try tournament(.oneSet, format: .teamAmericano, players: 2, rounds: 1)
        let id = t.rounds[0].matches[0].id
        try play("aaab", &t, id)
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(Tournament.self, from: data)
        #expect(decoded == t)
        var copy = decoded
        #expect(copy.repairCaches() == 0)
    }

    @Test("Rest points and invalid sets rules are rejected")
    func validation() {
        let players = Fixtures.players(5)
        var config = TournamentConfiguration(scoring: .sets(.oneSet), restCompensation: .halfMatchTotal)
        #expect(ConfigurationValidator.errors(TournamentDraft(name: "X", configuration: config, players: players)).contains { $0.code == .restCompensationNeedsTotalPoints })
        config = TournamentConfiguration(scoring: .sets(SetsRules(setsToWin: 0)))
        #expect(ConfigurationValidator.errors(TournamentDraft(name: "X", configuration: config, players: players)).contains { $0.code == .invalidSetsRules })
    }
}
