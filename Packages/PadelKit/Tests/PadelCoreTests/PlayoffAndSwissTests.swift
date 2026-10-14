import Foundation
import Testing
@testable import PadelCore

@Suite("Knockout playoffs and Swiss")
struct PlayoffAndSwissTests {
    let context = Fixtures.context()

    func tournament(format: TournamentFormat = .americano, players: Int = 8, courts: Int = 2, rounds: Int = 3, playoff: PlayoffSize, points: Int = 24, scoring: ScoringRule? = nil) throws -> Tournament {
        let config = TournamentConfiguration(format: format, courtCount: courts, roundCount: rounds, scoring: scoring ?? .totalPoints(points), seed: 4, playoff: playoff)
        let draft: TournamentDraft
        if format.usesTeams {
            let fixture = Fixtures.teams(players)
            draft = TournamentDraft(name: "P", configuration: config, players: fixture.players, teams: fixture.teams)
        } else if format.usesGroups {
            draft = TournamentDraft(name: "P", configuration: config, players: Fixtures.mixedPlayers(a: players / 2, b: players / 2))
        } else {
            draft = TournamentDraft(name: "P", configuration: config, players: Fixtures.players(players))
        }
        return try Tournament.create(from: draft, context: context)
    }

    /// Completes regular rounds with results that make the standings strictly ordered.
    func playRegular(_ t: inout Tournament) throws {
        var random = SeededGenerator(seed: 12)
        while let round = t.currentRound, round.kind != .knockout {
            try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        }
    }

    /// Plays the knockout stage with side A always winning (odd totals, no draws).
    func playKnockout(_ t: inout Tournament) throws {
        while let round = t.currentRound, round.kind == .knockout {
            let total = t.scoringRule(for: round.matches[0]).totalPoints!
            for match in round.matches {
                try t.enterResult(Score(a: total / 2 + 1, b: total - total / 2 - 1), for: match.id, context: context)
            }
        }
    }

    @Test("Bracket order keeps the top two seeds apart until the final")
    func bracketOrder() {
        #expect(Tournament.bracketOrder(2) == [0, 1])
        #expect(Tournament.bracketOrder(4) == [0, 3, 1, 2])
        #expect(Tournament.bracketOrder(8) == [0, 7, 3, 4, 1, 6, 2, 5])
    }

    @Test("Semifinals: seeded pairs from the standings, then a final between the winners")
    func semifinals() throws {
        var t = try tournament(playoff: .semifinals)
        #expect(t.configuration.totalRoundCount == 5)
        try playRegular(&t)
        let semis = try #require(t.currentRound)
        #expect(semis.kind == .knockout)
        #expect(t.knockoutStage(of: semis) == .semifinal)
        #expect(semis.matches.count == 2)
        // Seeds 1+8 v 4+5 and 2+7 v 3+6.
        let ranking = StandingsCalculator.compute(t).playerRanking
        let first = semis.matches[0]
        #expect(Set(first.sideA.playerIDs) == Set([ranking[0], ranking[7]]))
        #expect(Set(first.sideB.playerIDs) == Set([ranking[3], ranking[4]]))
        #expect(Set(semis.matches[1].sideA.playerIDs) == Set([ranking[1], ranking[6]]))
        // Knockout matches use an odd total so they cannot end level.
        #expect(t.scoringRule(for: first) == .totalPoints(25))
        try playKnockout(&t)
        #expect(t.rounds.count == 5)
        let final = try #require(t.rounds.last)
        #expect(t.knockoutStage(of: final) == .final)
        #expect(final.matches.count == 1)
        #expect(final.matches[0].sideA == semis.matches[0].sideA)
        #expect(final.matches[0].sideB == semis.matches[1].sideA)
        #expect(t.allRoundsCompleted)
        #expect(t.playoffChampion == final.matches[0].sideA)
        #expect(t.playoffRunnerUp == final.matches[0].sideB)
        // Knockout results do not change the standings.
        #expect(StandingsCalculator.compute(t).playerRanking == ranking)
        #expect(ResultSummary.text(for: t).contains("Playoff winners"))
        #expect(Invariants.check(t).isEmpty)
    }

    @Test("Quarterfinals for fixed teams and courts reused when there are fewer courts")
    func quarterfinalsTeams() throws {
        var t = try tournament(format: .teamAmericano, players: 8, courts: 2, rounds: 7, playoff: .quarterfinals)
        try playRegular(&t)
        let quarters = try #require(t.currentRound)
        #expect(t.knockoutStage(of: quarters) == .quarterfinal)
        #expect(quarters.matches.count == 4)
        #expect(quarters.matches.map(\.court) == [1, 2, 1, 2])
        try playKnockout(&t)
        #expect(t.rounds.suffix(3).map { t.knockoutStage(of: $0) } == [.quarterfinal, .semifinal, .final])
        #expect(t.playoffChampion?.teamID != nil)
    }

    @Test("Mixed playoffs pair one player from each group")
    func mixedPlayoff() throws {
        var t = try tournament(format: .mixedAmericano, players: 8, playoff: .final)
        try playRegular(&t)
        let final = try #require(t.currentRound)
        for side in [final.matches[0].sideA, final.matches[0].sideB] {
            #expect(Set(side.playerIDs.compactMap { t.player($0)?.group }) == [.a, .b])
        }
    }

    @Test("Timed knockout matches cannot be finished level")
    func timedKnockoutNeedsWinner() throws {
        var t = try tournament(playoff: .final, scoring: .timed(minutes: 10))
        try playRegular(&t)
        let match = try #require(t.currentRound?.matches.first)
        try t.recordPoint(for: .a, in: match.id, context: context)
        try t.recordPoint(for: .b, in: match.id, context: context)
        #expect(throws: TournamentError.scoring(.drawNotAllowed)) { try t.finishMatch(match.id, context: context) }
        #expect(throws: TournamentError.scoring(.drawNotAllowed)) { try t.enterResult(Score(a: 5, b: 5), for: match.id, context: context) }
        try t.recordPoint(for: .a, in: match.id, context: context)
        try t.finishMatch(match.id, context: context)
        #expect(t.playoffChampion != nil)
    }

    @Test("Reopening a semifinal withdraws the unplayed final")
    func reopenRemovesFinal() throws {
        var t = try tournament(playoff: .semifinals)
        try playRegular(&t)
        // Play only the semifinals.
        for match in t.rounds[3].matches {
            try t.enterResult(Score(a: 13, b: 12), for: match.id, context: context)
        }
        #expect(t.rounds.count == 5)
        // Correct a semifinal while the final has not started: the final is rebuilt.
        let semi = t.rounds[3].matches[0]
        try t.reopenMatch(semi.id, context: context)
        #expect(t.rounds.count == 4)
        try t.enterResult(Score(a: 5, b: 20), for: semi.id, context: context)
        #expect(t.rounds.count == 5)
        #expect(t.rounds[4].matches[0].sideA == semi.sideB)
    }

    @Test("Validation: playoffs need enough pairs and exclude the final round option")
    func validation() {
        var config = TournamentConfiguration(roundCount: 3, playoff: .quarterfinals)
        #expect(ConfigurationValidator.errors(TournamentDraft(name: "X", configuration: config, players: Fixtures.players(12))).contains { $0.code == .notEnoughForPlayoff })
        config.playoff = .semifinals
        config.standingsBasedFinalRound = true
        #expect(ConfigurationValidator.errors(TournamentDraft(name: "X", configuration: config, players: Fixtures.players(12))).contains { $0.code == .playoffAndFinalRound })
    }

    @Test("Tournaments saved before playoffs existed still load")
    func backwardCompatibleDecoding() throws {
        let old = #"{"format":"americano","courtCount":2,"roundCount":3,"scoring":{"totalPoints":{"_0":24}},"mixedLabels":{"groupA":"A","groupB":"B"},"mexicanoPattern":"oneFourVsTwoThree","mexicanoFirstRound":"random","standingsBasedFinalRound":false,"restCompensation":"none","seed":5}"#
        let config = try JSONDecoder().decode(TournamentConfiguration.self, from: Data(old.utf8))
        #expect(config.playoff == .none)
        #expect(config.totalRoundCount == 3)
    }

    // MARK: Swiss

    @Test("Swiss: teams with the same record meet and nobody meets twice")
    func swiss() throws {
        var t = try tournament(format: .swiss, players: 8, courts: 4, rounds: 4, playoff: .none)
        #expect(t.rounds.count == 1)
        var random = SeededGenerator(seed: 3)
        while t.currentRound != nil {
            try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        }
        #expect(t.rounds.count == 4)
        #expect(ScheduleMetrics.of(t).opponentRepeats == 0)
        #expect(Invariants.check(t).isEmpty)
        let standings = StandingsCalculator.compute(t)
        #expect(standings.tieBreakers.first == .wins)
        // Ranked by wins first.
        for pair in zip(standings.entries, standings.entries.dropFirst()) {
            #expect(pair.0.wins >= pair.1.wins)
        }
    }

    @Test("Swiss with a playoff")
    func swissPlayoff() throws {
        var t = try tournament(format: .swiss, players: 8, courts: 4, rounds: 3, playoff: .semifinals)
        try playRegular(&t)
        try playKnockout(&t)
        #expect(t.playoffChampion != nil)
    }
}

@Suite("Playoff settings")
struct PlayoffSettingsTests {
    @Test("Playoffs can be added mid-tournament and are locked once started")
    func changePlayoff() throws {
        let context = Fixtures.context()
        var t = try Fixtures.tournament(players: 8, courts: 2, rounds: 2)
        try t.updateSettings(playoff: .final, context: context)
        #expect(t.configuration.totalRoundCount == 3)
        var random = SeededGenerator(seed: 1)
        try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        #expect(t.currentRound?.kind == .knockout)
        try t.recordPoint(for: .a, in: t.currentRound!.matches[0].id, context: context)
        #expect(throws: TournamentError.self) { try t.updateSettings(playoff: .none, context: context) }
    }
}
