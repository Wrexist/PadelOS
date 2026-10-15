import Foundation
import Testing
@testable import PadelCore

@Suite("Player records across tournaments")
struct PlayerRecordsTests {
    let context = Fixtures.context()

    /// A tournament with the given player names, created `day` days after the fixture start.
    func tournament(
        _ names: [String],
        day: Int,
        format: TournamentFormat = .americano,
        rounds: Int = 3,
        scoring: ScoringRule = .totalPoints(24),
        teams: [[Int]] = [],
        playoff: PlayoffSize = .none
    ) throws -> Tournament {
        let ids = SequentialIdentifierGenerator(seed: UInt64(200 + day))
        let players = names.map { Player(id: PlayerID(ids.next()), name: $0) }
        let fixedTeams = teams.enumerated().map { index, members in
            Team(id: TeamID(ids.next()), name: "Team \(index + 1)", playerIDs: members.map { players[$0].id })
        }
        let courts = max(1, (format.usesTeams ? fixedTeams.count : names.count) / (format.usesTeams ? 2 : 4))
        let config = TournamentConfiguration(format: format, courtCount: courts, roundCount: rounds, scoring: scoring, seed: 3, playoff: playoff)
        let draft = TournamentDraft(name: "Day \(day)", configuration: config, players: players, teams: fixedTeams)
        let created = EngineContext(now: Fixtures.start.addingTimeInterval(Double(day) * 86_400), deviceID: context.deviceID, ids: ids)
        return try Tournament.create(from: draft, context: created)
    }

    func id(_ t: Tournament, _ name: String) throws -> PlayerID {
        try #require(t.players.first { $0.name == name }).id
    }

    /// Plays every regular round; `winner`'s side scores 20–4 (or loses 4–20 if `loses`).
    func play(_ t: inout Tournament, winner name: String, loses: Bool = false) throws {
        let player = try id(t, name)
        while let round = t.currentRound, round.kind != .knockout {
            for match in round.matches where !match.isCompleted {
                let side = match.side(of: player) ?? .a
                let good = loses ? 4 : 20, bad = 24 - good
                try t.enterResult(side == .a ? Score(a: good, b: bad) : Score(a: bad, b: good), for: match.id, context: context)
            }
        }
    }

    func record(_ records: [PlayerRecord], _ name: String) throws -> PlayerRecord {
        try #require(records.first { $0.key == PlayerKey(name: name) })
    }

    @Test("Names match trimmed and ignoring case, accents, width and extra spaces")
    func nameMatching() throws {
        #expect(PlayerKey(name: "  José   García ") == PlayerKey(name: "jose garcia"))
        #expect(PlayerKey(name: "ÅSA") == PlayerKey(name: "asa"))
        #expect(PlayerKey(name: "Ｍａｊａ") == PlayerKey(name: "Maja"))
        #expect(PlayerKey(name: "Jose Garcias") != PlayerKey(name: "José García"))
        #expect(PlayerKey(name: "   ").rawValue.isEmpty)

        var first = try tournament(["José García", "Lisa", "Johan", "Maja"], day: 0)
        try play(&first, winner: "José García")
        var second = try tournament(["  jose   GARCIA ", "lisa", "Johan", "Maja"], day: 1)
        try play(&second, winner: "jose   GARCIA", loses: true)

        let records = PlayerRecords.compute([second, first])
        #expect(records.count == 4)
        let jose = try record(records, "Jose Garcia")
        #expect(jose.tournamentsPlayed == 2)
        #expect(jose.name == "jose GARCIA", "the latest spelling is shown, spaces collapsed")
        #expect(jose.matchesPlayed == 6)
        #expect(jose.wins == 3 && jose.losses == 3 && jose.draws == 0)
        #expect(jose.winRate == 0.5)
        #expect(jose.pointsFor == 3 * 20 + 3 * 4 && jose.pointsAgainst == 3 * 4 + 3 * 20)
        // Form: the last five results, oldest first.
        #expect(jose.form == [.win, .win, .loss, .loss, .loss])
        // History: newest first.
        #expect(jose.tournaments.map(\.tournamentName) == ["Day 1", "Day 0"])
        #expect(jose.tournaments[0].wins == 0 && jose.tournaments[0].losses == 3)
        #expect(try record(records, "LISA").tournamentsPlayed == 2)

        // Search uses the same normalisation.
        #expect(PlayerRecords.filter(records, query: "GARCÍA").map(\.key) == [jose.key])
        #expect(PlayerRecords.filter(records, query: "  ").count == 4)
        #expect(PlayerRecords.record(for: PlayerKey(name: "JOSÉ GARCÍA"), in: [first, second])?.matchesPlayed == 6)
    }

    @Test("Tournament wins and podiums count only completed tournaments")
    func winsAndPodiums() throws {
        var t = try tournament(["Alex", "Lisa", "Johan", "Maja"], day: 0)
        try play(&t, winner: "Alex")

        // Still running: positions are shown, but nothing is won yet.
        var alex = try record(PlayerRecords.compute([t]), "Alex")
        #expect(alex.tournaments[0].rank == 1)
        #expect(alex.tournaments[0].isCompleted == false)
        #expect(alex.tournamentWins == 0 && alex.podiums == 0)

        t.finish(now: Fixtures.start)
        let records = PlayerRecords.compute([t])
        alex = try record(records, "Alex")
        #expect(alex.tournamentWins == 1 && alex.podiums == 1)
        #expect(alex.wins == 3 && alex.matchesPlayed == 3)
        #expect(alex.tournaments[0].isWin)
        // The other three share second place: a podium, not a win.
        let lisa = try record(records, "Lisa")
        #expect(lisa.tournaments[0].rank == 2 && lisa.tournaments[0].isTied)
        #expect(lisa.tournamentWins == 0 && lisa.podiums == 1)
        #expect(lisa.wins == 1 && lisa.losses == 2)

        // Leaderboard orders.
        #expect(PlayerRecords.sorted(records, by: .wins).first?.name == "Alex")
        #expect(PlayerRecords.sorted(records, by: .winRate).first?.name == "Alex")
        #expect(PlayerRecords.sorted(records, by: .wins).map(\.name) == ["Alex", "Johan", "Lisa", "Maja"])
    }

    @Test("A decided playoff decides the winner, not the regular standings")
    func playoffChampion() throws {
        var t = try tournament(["Alex", "Lisa", "Johan", "Maja", "Erik", "Sofia", "Daniel", "Nora"], day: 0, playoff: .final)
        var random = SeededGenerator(seed: 5)
        while let round = t.currentRound, round.kind != .knockout {
            try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        }
        let ranking = StandingsCalculator.compute(t).playerRanking
        let final = try #require(t.currentRound?.matches.first)
        // Seeds 2 and 3 (side B) beat seeds 1 and 4.
        #expect(Set(final.sideB.playerIDs) == Set([ranking[1], ranking[2]]))
        try t.enterResult(Score(a: 12, b: 13), for: final.id, context: context)
        t.finish(now: Fixtures.start)

        let records = PlayerRecords.compute([t])
        func entry(_ id: PlayerID) throws -> PlayerTournamentRecord {
            try #require(try record(records, t.playerName(id)).tournaments.first)
        }
        #expect(try entry(ranking[1]).rank == 1)
        #expect(try entry(ranking[2]).isWin)
        #expect(try entry(ranking[0]).rank == 2, "top of the standings, but lost the final")
        #expect(try entry(ranking[0]).isWin == false)
        #expect(try entry(ranking[3]).rank == 2)
        let standings = StandingsCalculator.compute(t)
        for outside in ranking.dropFirst(4) {
            #expect(try entry(outside).rank == standings.entry(for: .player(outside))?.rank, "players outside the playoff keep their standings position")
        }
        #expect(try record(records, t.playerName(ranking[1])).tournamentWins == 1)
        // The final is a match like any other.
        #expect(try entry(ranking[0]).matchesPlayed == 4)
    }

    @Test("Team formats credit both members; best partner and most frequent opponent")
    func teamsPartnersAndOpponents() throws {
        var americano = try tournament(["Alex", "Lisa", "Johan", "Maja"], day: 0)
        try play(&americano, winner: "Alex")
        americano.finish(now: Fixtures.start)
        var teams = try tournament(["Alex", "Lisa", "Johan", "Maja"], day: 1, format: .teamAmericano, teams: [[0, 1], [2, 3]])
        try play(&teams, winner: "Alex")
        teams.finish(now: Fixtures.start)

        let records = PlayerRecords.compute([americano, teams])
        let alex = try record(records, "Alex")
        #expect(alex.tournamentsPlayed == 2 && alex.tournamentWins == 2)
        #expect(alex.matchesPlayed == 6 && alex.wins == 6)
        // Lisa: one win together in the Americano, three as a fixed team.
        #expect(alex.bestPartner?.name == "Lisa")
        #expect(alex.bestPartner?.wins == 4 && alex.bestPartner?.matches == 4)
        // Johan and Maja were each faced five times; the tie goes to the first name.
        #expect(alex.mostFrequentOpponent?.name == "Johan")
        #expect(alex.mostFrequentOpponent?.matches == 5 && alex.mostFrequentOpponent?.wins == 5)

        // Team members share the team's result and position.
        let lisa = try record(records, "Lisa")
        #expect(lisa.tournaments[0].rank == 1 && lisa.tournaments[0].wins == 3)
        #expect(lisa.tournamentWins == 1 && lisa.podiums == 2)
        let maja = try record(records, "Maja")
        #expect(maja.tournaments[0].rank == 2 && maja.tournaments[0].losses == 3)
        #expect(maja.tournaments[0].format == .teamAmericano)
        // Nobody won with Maja in the team tournament; her only win came with Alex.
        #expect(maja.bestPartner?.name == "Alex")
        #expect(maja.bestPartner?.wins == 1)
    }

    @Test("Games and sets count games; the match winner is decided by sets")
    func setsScoring() throws {
        var t = try tournament(["Alex", "Lisa", "Johan", "Maja"], day: 0, rounds: 2, scoring: .sets(.bestOfThree))
        let first = try #require(t.currentRound?.matches.first)
        try t.enterSetsResult([Score(a: 6, b: 4), Score(a: 6, b: 3)], for: first.id, context: context)
        let second = try #require(t.currentRound?.matches.first)
        // Side A wins 0–6, 7–6, 7–6 with fewer games (14–18).
        try t.enterSetsResult([Score(a: 0, b: 6), Score(a: 7, b: 6), Score(a: 7, b: 6)], for: second.id, context: context)

        let records = PlayerRecords.compute([t])
        let player = second.sideA.playerIDs[0]
        let rec = try record(records, t.playerName(player))
        let firstGames = first.side(of: player) == .a ? (12, 7) : (7, 12)
        #expect(rec.gamesFor == firstGames.0 + 14)
        #expect(rec.gamesAgainst == firstGames.1 + 18)
        #expect(rec.pointsFor == 0 && rec.pointsAgainst == 0)
        #expect(rec.tournaments[0].countsGames)
        #expect(rec.tournaments[0].scoredFor == rec.gamesFor)
        #expect(rec.form.last == .win)
        let loser = try record(records, t.playerName(second.sideB.playerIDs[0]))
        #expect(loser.form.last == .loss)
    }

    @Test("Unplayed matches never count, including a withdrawn player's")
    func withdrawnAndUnplayed() throws {
        var t = try Fixtures.tournament(players: 5, courts: 1, rounds: 5)
        var random = SeededGenerator(seed: 9)
        try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        let leaving = try #require(t.rounds.first?.matches.first?.sideA.playerIDs.first)
        try t.withdrawPlayer(leaving, context: context)
        try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        // Finished early: rounds 3–5 are never played.
        t.finish(now: Fixtures.start)

        let records = PlayerRecords.compute([t])
        #expect(try record(records, t.playerName(leaving)).matchesPlayed == 1)
        #expect(records.reduce(0) { $0 + $1.matchesPlayed } == 2 * 4)
        // A player who has not finished a match yet has no record.
        let idle = t.players.filter { player in !t.allMatches.contains { $0.isCompleted && $0.allPlayerIDs.contains(player.id) } }
        for player in idle {
            #expect(records.contains { $0.key == PlayerKey(name: player.name) } == false)
        }
    }

    @Test("No tournaments or no results: no records")
    func emptyHistory() throws {
        #expect(PlayerRecords.compute([]).isEmpty)
        let fresh = try tournament(["Alex", "Lisa", "Johan", "Maja"], day: 0)
        #expect(PlayerRecords.compute([fresh]).isEmpty)
        #expect(PlayerRecords.record(for: PlayerKey(name: "Alex"), in: [fresh]) == nil)
        #expect(PlayerRecords.sorted([], by: .matches).isEmpty)
    }
}
