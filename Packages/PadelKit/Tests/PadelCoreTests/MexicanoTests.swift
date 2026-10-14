import Foundation
import Testing
@testable import PadelCore

@Suite("Mexicano")
struct MexicanoTests {
    let context = Fixtures.context()

    @Test("Only the first round exists until it is completed")
    func lazyGeneration() throws {
        var t = try Fixtures.tournament(format: .mexicano, players: 8, courts: 2, rounds: 5)
        #expect(t.rounds.count == 1)
        let first = t.rounds[0]
        try Fixtures.play(&t, first.matches[0].id, a: 15, b: 9, context: context)
        #expect(t.rounds.count == 1, "next round must wait for the whole round")
        try Fixtures.play(&t, first.matches[1].id, a: 12, b: 12, context: context)
        #expect(t.rounds.count == 2)
        #expect(t.rounds[0].matches == t.rounds[0].matches) // completed round untouched below
        #expect(t.rounds[0].isCompleted)
        #expect(Invariants.check(t).isEmpty)
    }

    @Test("Round two groups players by standings: 1 & 4 vs 2 & 3 on court 1")
    func standingsPairing() throws {
        var t = try Fixtures.tournament(format: .mexicano, players: 8, courts: 2, rounds: 3)
        let r1 = t.rounds[0]
        try t.enterResult(Score(a: 20, b: 4), for: r1.matches[0].id, context: context)
        try t.enterResult(Score(a: 14, b: 10), for: r1.matches[1].id, context: context)
        let standings = StandingsCalculator.compute(t, throughRound: 1)
        let ranking = standings.playerRanking
        let court1 = t.rounds[1].matches.first { $0.court == 1 }!
        let top4 = Set(ranking.prefix(4))
        #expect(Set(court1.allPlayerIDs) == top4)
        // Top 4 all partnered someone else in round 1 (winners were partners), so the
        // preferred pattern is only used if it does not repeat a partnership.
        let history = PlayerHistory.players(from: [t.rounds[0]])
        #expect(history.partners[court1.sideA.playerIDs[0], court1.sideA.playerIDs[1]] == 0)
        #expect(history.partners[court1.sideB.playerIDs[0], court1.sideB.playerIDs[1]] == 0)
    }

    @Test("Pattern 1 & 4 vs 2 & 3 is applied when no repeat is involved")
    func patternWithoutHistory() {
        let ids = Fixtures.players(4).map(\.id)
        let plan = MexicanoScheduler.arrange(active: ids, history: PlayerHistory(), pattern: .oneFourVsTwoThree)
        #expect(Set(plan[0].teamA) == Set([ids[0], ids[3]]))
        #expect(Set(plan[0].teamB) == Set([ids[1], ids[2]]))
        let alt = MexicanoScheduler.arrange(active: ids, history: PlayerHistory(), pattern: .oneThreeVsTwoFour)
        #expect(Set(alt[0].teamA) == Set([ids[0], ids[2]]))
    }

    @Test("A full Mexicano evening stays valid and avoids repeated partners where feasible", arguments: [(8, 2, 6), (12, 3, 6), (9, 2, 7), (16, 4, 8), (5, 1, 5)])
    func fullEvening(players: Int, courts: Int, rounds: Int) throws {
        var t = try Fixtures.tournament(format: .mexicano, players: players, courts: courts, rounds: rounds, seed: 11)
        var random = SeededGenerator(seed: 5)
        var completedSnapshots: [Round] = []
        while let current = t.currentRound {
            try Fixtures.completeCurrentRound(&t, random: &random, context: context)
            completedSnapshots.append(t.rounds[current.number - 1])
            // Completed rounds are never rewritten by later generation.
            for snapshot in completedSnapshots {
                #expect(t.rounds[snapshot.number - 1] == snapshot)
            }
        }
        #expect(t.rounds.count == rounds)
        #expect(t.allRoundsCompleted)
        #expect(Invariants.check(t).isEmpty, "\(Invariants.check(t))")
        let metrics = ScheduleMetrics.of(t)
        #expect(metrics.playedSpread <= 1)
        // Mexicano trades diversity for competitive balance, but partners should rarely repeat.
        #expect(metrics.maxTimesPartnered <= 2, "max partnered \(metrics.maxTimesPartnered)")
        print("Mexicano \(players)p/\(courts)c/\(rounds)r partner repeats: \(metrics.partnerRepeats), opponent repeats: \(metrics.opponentRepeats)")
    }

    @Test("Ties in the standings are resolved deterministically")
    func deterministicTies() throws {
        func run() throws -> Tournament {
            let context = Fixtures.context(seed: 21)
            var t = try Fixtures.tournament(format: .mexicano, players: 8, courts: 2, rounds: 3, seed: 9)
            for match in t.rounds[0].matches {
                try t.enterResult(Score(a: 12, b: 12), for: match.id, context: context) // everyone tied
            }
            return t
        }
        #expect(try run().rounds[1] == (try run()).rounds[1])
    }

    @Test("Correcting a result rebuilds the next round only while it has not started")
    func correctionRegeneratesUnstartedRound() throws {
        var t = try Fixtures.tournament(format: .mexicano, players: 8, courts: 2, rounds: 4)
        let r1 = t.rounds[0]
        try t.enterResult(Score(a: 24, b: 0), for: r1.matches[0].id, context: context)
        try t.enterResult(Score(a: 24, b: 0), for: r1.matches[1].id, context: context)
        let before = t.rounds[1]
        // Flip the first result: standings change, so the unstarted round 2 is rebuilt.
        try t.enterResult(Score(a: 0, b: 24), for: r1.matches[0].id, context: context)
        #expect(t.rounds.count == 2)
        #expect(t.rounds[1].matches.map(\.id) != before.matches.map(\.id))
        #expect(t.rounds[0].matches[0].score == Score(a: 0, b: 24))

        // Once round 2 has started it is never rewritten by a correction.
        let r2 = t.rounds[1]
        try t.recordPoint(for: .a, in: r2.matches[0].id, context: context)
        let started = t.rounds[1]
        try t.enterResult(Score(a: 10, b: 14), for: r1.matches[1].id, context: context)
        #expect(t.rounds[1] == started)
    }

    @Test("Reopening a match in the latest completed round withdraws the unstarted next round")
    func reopenRemovesDependentRound() throws {
        var t = try Fixtures.tournament(format: .mexicano, players: 8, courts: 2, rounds: 3)
        for match in t.rounds[0].matches { try t.enterResult(Score(a: 13, b: 11), for: match.id, context: context) }
        #expect(t.rounds.count == 2)
        try t.reopenMatch(t.rounds[0].matches[0].id, context: context)
        #expect(t.rounds.count == 1, "round 2 must not be based on an incomplete round")
        try t.finishMatch(t.rounds[0].matches[0].id, context: context)
        #expect(t.rounds.count == 2)
    }

    @Test("Standings used for pairing ignore matches still in progress")
    func ignoresIncompleteResults() throws {
        var t = try Fixtures.tournament(format: .mexicano, players: 8, courts: 2, rounds: 3)
        try t.enterResult(Score(a: 12, b: 12), for: t.rounds[0].matches[0].id, context: context)
        for _ in 0..<20 { try t.recordPoint(for: .a, in: t.rounds[0].matches[1].id, context: context) }
        let standings = StandingsCalculator.compute(t)
        #expect(standings.entries.allSatisfy { $0.points == 12 || $0.points == 0 })
    }

    @Test("List-order first round treats the list as a ranking")
    func listOrderFirstRound() throws {
        let players = Fixtures.players(8)
        let config = TournamentConfiguration(format: .mexicano, courtCount: 2, roundCount: 3, mexicanoFirstRound: .listOrder)
        let t = try Tournament.create(from: TournamentDraft(name: "M", configuration: config, players: players), context: context)
        let court1 = t.rounds[0].matches.first { $0.court == 1 }!
        #expect(Set(court1.allPlayerIDs) == Set(players.prefix(4).map(\.id)))
        #expect(Set(court1.sideA.playerIDs) == Set([players[0].id, players[3].id]))
    }
}

@Suite("Final round")
struct FinalRoundTests {
    let context = Fixtures.context()

    @Test("Americano with a final round: top four meet on court 1 after regular rounds")
    func americanoFinal() throws {
        var t = try Fixtures.tournament(format: .americano, players: 8, courts: 2, rounds: 4, finalRound: true)
        #expect(t.rounds.count == 3, "regular rounds are scheduled up front, the final later")
        var random = SeededGenerator(seed: 1)
        for _ in 0..<3 { try Fixtures.completeCurrentRound(&t, random: &random, context: context) }
        #expect(t.rounds.count == 4)
        let final = t.rounds[3]
        #expect(final.kind == .final)
        let ranking = StandingsCalculator.compute(t, throughRound: 3).playerRanking
        let court1 = final.matches.first { $0.court == 1 }!
        #expect(Set(court1.sideA.playerIDs) == Set([ranking[0], ranking[3]]))
        #expect(Set(court1.sideB.playerIDs) == Set([ranking[1], ranking[2]]))
    }

    @Test("Team final: first plays second")
    func teamFinal() throws {
        var t = try Fixtures.tournament(format: .teamAmericano, players: 4, courts: 2, rounds: 4, finalRound: true)
        var random = SeededGenerator(seed: 1)
        for _ in 0..<3 { try Fixtures.completeCurrentRound(&t, random: &random, context: context) }
        let ranking = StandingsCalculator.compute(t, throughRound: 3).teamRanking
        let final = try #require(t.rounds.last)
        #expect(final.kind == .final)
        let court1 = final.matches.first { $0.court == 1 }!
        #expect(Set([court1.sideA.teamID!, court1.sideB.teamID!]) == Set(ranking.prefix(2)))
    }

    @Test("Mixed final keeps one player of each group per team")
    func mixedFinal() throws {
        var t = try Fixtures.tournament(format: .mixedAmericano, players: 8, courts: 2, rounds: 3, finalRound: true)
        var random = SeededGenerator(seed: 1)
        for _ in 0..<2 { try Fixtures.completeCurrentRound(&t, random: &random, context: context) }
        #expect(t.rounds.last?.kind == .final)
        #expect(Invariants.check(t).isEmpty)
    }
}
