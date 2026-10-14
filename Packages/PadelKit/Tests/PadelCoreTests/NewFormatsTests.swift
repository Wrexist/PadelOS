import Foundation
import Testing
@testable import PadelCore

@Suite("Mixicano, Team Mexicano, King of the Court")
struct NewFormatsTests {
    let context = Fixtures.context()

    /// Plays the whole tournament with deterministic random results, checking that every
    /// generated round is valid and completed rounds never change.
    func playThrough(_ t: inout Tournament, seed: UInt64 = 5) throws {
        var random = SeededGenerator(seed: seed)
        var completed: [Round] = []
        while let current = t.currentRound {
            #expect(Invariants.check(t).isEmpty, "\(Invariants.check(t))")
            try Fixtures.completeCurrentRound(&t, random: &random, context: context)
            completed.append(t.rounds[current.number - 1])
            for snapshot in completed { #expect(t.rounds[snapshot.number - 1] == snapshot) }
        }
        #expect(t.allRoundsCompleted)
    }

    @Test("Formats are classified correctly")
    func classification() {
        #expect(TournamentFormat.mixicano.usesGroups && TournamentFormat.mixicano.isIndividual)
        #expect(TournamentFormat.teamMexicano.usesTeams && !TournamentFormat.teamMexicano.isIndividual)
        #expect(!TournamentFormat.kingOfTheCourt.hasPrecomputedSchedule)
        #expect(TournamentFormat.allCases.count == 7)
    }

    // MARK: Mixicano

    @Test("Mixicano: one of each group per team, generated round by round", arguments: [(8, 2, 6), (12, 3, 6), (10, 2, 5)])
    func mixicano(players: Int, courts: Int, rounds: Int) throws {
        var t = try Fixtures.tournament(format: .mixicano, players: players, courts: courts, rounds: rounds, seed: 3)
        #expect(t.rounds.count == 1)
        try playThrough(&t)
        #expect(t.rounds.count == rounds)
        let history = PlayerHistory.players(from: t.rounds)
        for group in PlayerGroup.allCases {
            let played = t.players.filter { $0.group == group }.map { history.playedCount($0.id) }
            #expect((played.max() ?? 0) - (played.min() ?? 0) <= 1)
        }
        #expect(ScheduleMetrics.of(t).maxTimesPartnered <= 2)
    }

    @Test("Mixicano: court 1 hosts the top two of each group, strongest paired with weaker")
    func mixicanoPairing() throws {
        var t = try Fixtures.tournament(format: .mixicano, players: 8, courts: 2, rounds: 3)
        for match in t.rounds[0].matches { try t.enterResult(Score(a: 20, b: 4), for: match.id, context: context) }
        let ranking = StandingsCalculator.compute(t, throughRound: 1).playerRanking
        let topA = ranking.filter { t.player($0)?.group == .a }.prefix(2)
        let topB = ranking.filter { t.player($0)?.group == .b }.prefix(2)
        let court1 = try #require(t.rounds[1].matches.first { $0.court == 1 })
        #expect(Set(court1.allPlayerIDs) == Set(topA + topB))
        #expect(Invariants.check(t).isEmpty)
    }

    // MARK: Team Mexicano

    @Test("Team Mexicano: 1st plays 2nd and repeat meetings are avoided when possible")
    func teamMexicano() throws {
        var t = try Fixtures.tournament(format: .teamMexicano, players: 6, courts: 3, rounds: 4)
        #expect(t.rounds.count == 1)
        let round1 = t.rounds[0]
        // Make the round-1 winners the top three teams.
        for (index, match) in round1.matches.enumerated() {
            try t.enterResult(Score(a: 24 - index * 2, b: index * 2), for: match.id, context: context)
        }
        let ranking = StandingsCalculator.compute(t, throughRound: 1).teamRanking
        let court1 = try #require(t.rounds[1].matches.first { $0.court == 1 })
        let pair = Set([court1.sideA.teamID!, court1.sideB.teamID!])
        #expect(pair.contains(ranking[0]))
        // No pairing from round 1 is repeated in round 2.
        let history = TeamHistory.teams(from: [round1])
        for match in t.rounds[1].matches {
            #expect(history.opponents[match.sideA.teamID!, match.sideB.teamID!] == 0)
        }
        try playThrough(&t)
        #expect(ScheduleMetrics.of(t).playedSpread <= 1)
    }

    @Test("Team Mexicano with an odd number of teams rests teams fairly")
    func teamMexicanoRests() throws {
        var t = try Fixtures.tournament(format: .teamMexicano, players: 5, courts: 2, rounds: 5)
        try playThrough(&t)
        let metrics = ScheduleMetrics.of(t)
        #expect(metrics.playedSpread <= 1)
        #expect(metrics.restSpread <= 1)
    }

    // MARK: King of the Court

    @Test("King of the Court: winners move up a court, losers move down, partners split")
    func ladderMovement() throws {
        var t = try Fixtures.tournament(format: .kingOfTheCourt, players: 12, courts: 3, rounds: 4)
        let round1 = t.rounds[0]
        for match in round1.matches { try t.enterResult(Score(a: 16, b: 8), for: match.id, context: context) }
        let round2 = try #require(t.rounds.last)
        #expect(round2.number == 2)
        func court(of player: PlayerID) -> Int? { round2.matches.first { $0.allPlayerIDs.contains(player) }?.court }
        for match in round1.matches {
            for winner in match.sideA.playerIDs {
                #expect(court(of: winner) == max(1, match.court - 1), "winner of court \(match.court)")
            }
            for loser in match.sideB.playerIDs {
                #expect(court(of: loser) == min(3, match.court + 1), "loser of court \(match.court)")
            }
        }
        // Nobody keeps their round-1 partner.
        let history = PlayerHistory.players(from: [round1])
        for match in round2.matches {
            #expect(history.partners[match.sideA.playerIDs[0], match.sideA.playerIDs[1]] == 0)
            #expect(history.partners[match.sideB.playerIDs[0], match.sideB.playerIDs[1]] == 0)
        }
    }

    @Test("King of the Court: a draw keeps both teams on their court")
    func ladderDraw() throws {
        var t = try Fixtures.tournament(format: .kingOfTheCourt, players: 8, courts: 2, rounds: 3)
        let round1 = t.rounds[0]
        for match in round1.matches { try t.enterResult(Score(a: 12, b: 12), for: match.id, context: context) }
        let round2 = try #require(t.rounds.last)
        for match in round1.matches {
            for player in match.allPlayerIDs {
                #expect(round2.matches.first { $0.allPlayerIDs.contains(player) }?.court == match.court)
            }
        }
    }

    @Test("King of the Court with extra players rotates rests fairly", arguments: [(10, 2, 8), (13, 3, 6), (9, 2, 6)])
    func ladderWithRests(players: Int, courts: Int, rounds: Int) throws {
        var t = try Fixtures.tournament(format: .kingOfTheCourt, players: players, courts: courts, rounds: rounds, seed: 9)
        try playThrough(&t)
        let metrics = ScheduleMetrics.of(t)
        #expect(metrics.playedSpread <= 1, "played spread \(metrics.playedSpread)")
    }

    @Test("King of the Court works with games and sets")
    func ladderWithSets() throws {
        let config = TournamentConfiguration(format: .kingOfTheCourt, courtCount: 2, roundCount: 2, scoring: .sets(.shortSet))
        var t = try Tournament.create(from: TournamentDraft(name: "KotC", configuration: config, players: Fixtures.players(8)), context: context)
        for match in t.rounds[0].matches {
            try t.enterSetsResult([Score(a: 4, b: 2)], for: match.id, context: context)
        }
        #expect(t.rounds.count == 2)
        #expect(Invariants.check(t).isEmpty)
    }

    @Test("Withdrawals and late players work in the new formats")
    func lifecycle() throws {
        var ladder = try Fixtures.tournament(format: .kingOfTheCourt, players: 9, courts: 2, rounds: 4)
        try ladder.withdrawPlayer(ladder.players[0].id, context: context)
        #expect(Invariants.check(ladder).isEmpty)
        var mixi = try Fixtures.tournament(format: .mixicano, players: 10, courts: 2, rounds: 4)
        try mixi.addPlayer(name: "Zed", group: .a, context: context)
        #expect(Invariants.check(mixi).isEmpty)
        var teams = try Fixtures.tournament(format: .teamMexicano, players: 4, courts: 2, rounds: 3)
        try teams.withdrawTeam(teams.teams[0].id, context: context)
        #expect(Invariants.check(teams).isEmpty)
    }

    @Test("Standings-based final round in the new formats", arguments: [TournamentFormat.mixicano, .teamMexicano, .kingOfTheCourt])
    func finals(format: TournamentFormat) throws {
        var t = try Fixtures.tournament(format: format, players: format.usesTeams ? 4 : 8, courts: 2, rounds: 3, finalRound: true)
        try playThrough(&t)
        #expect(t.rounds.last?.kind == .final)
    }

    @Test("King of the Court on one court warns that there is nothing to move between")
    func singleCourtWarning() {
        let draft = TournamentDraft(name: "K", configuration: TournamentConfiguration(format: .kingOfTheCourt, courtCount: 1, roundCount: 3), players: Fixtures.players(4))
        #expect(ConfigurationValidator.validate(draft).contains { $0.code == .singleCourtLadder && $0.severity == .warning })
    }
}
