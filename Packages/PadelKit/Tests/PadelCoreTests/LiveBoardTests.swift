import Foundation
import Testing
@testable import PadelCore

@Suite("Spectator board snapshot")
struct LiveBoardSnapshotTests {
    let context = Fixtures.context()
    let at = Date(timeIntervalSince1970: 1_800_000_600)

    @Test("Standings, round and courts of an Americano in progress")
    func americanoInProgress() throws {
        var t = try Fixtures.tournament(players: 10, courts: 2, rounds: 5, points: 16)
        let round1 = try #require(t.currentRound)
        try t.enterResult(Score(a: 10, b: 6), for: round1.matches[0].id, context: context)
        try t.enterResult(Score(a: 7, b: 9), for: round1.matches[1].id, context: context)
        let round2 = try #require(t.currentRound)
        #expect(round2.number == 2)
        try t.recordPoint(for: .a, in: round2.matches[0].id, context: context)
        try t.recordPoint(for: .a, in: round2.matches[0].id, context: context)
        try t.recordPoint(for: .b, in: round2.matches[0].id, context: context)

        let board = LiveBoardSnapshot(tournament: t, updatedAt: at)
        #expect(board.name == "Test")
        #expect(board.format == "americano")
        #expect(board.formatName == "Americano")
        #expect(board.status == .active)
        #expect(board.round == 2)
        #expect(board.rounds == 5)
        #expect(board.stage == .regular)
        #expect(!board.countsGames)

        let standings = StandingsCalculator.compute(t)
        #expect(board.standings.count == 10)
        #expect(board.standings.map(\.name) == standings.entries.map(\.name))
        let leader = try #require(board.standings.first)
        #expect(leader.rank == 1 && leader.points == 10 && leader.won == 1 && leader.drawn == 0 && leader.lost == 0 && leader.difference == 4)

        #expect(board.courts.map(\.court) == [1, 2])
        let live = board.courts[0]
        #expect(live.state == .live)
        #expect(live.teamA == t.sideName(round2.matches[0].sideA))
        #expect(live.scoreA == "2" && live.scoreB == "1")
        #expect(live.sets == nil)
        let upcoming = board.courts[1]
        #expect(upcoming.state == .upcoming)
        #expect(upcoming.scoreA.isEmpty && upcoming.scoreB.isEmpty)
        #expect(board.resting.count == 2)
        #expect(Set(board.resting).isSubset(of: Set(t.players.map(\.name))))
        #expect(board.champion == nil)
    }

    @Test("Games and sets: current game points as big figures, sets as detail")
    func setsScoring() throws {
        let config = TournamentConfiguration(format: .americano, courtCount: 1, roundCount: 3, scoring: .sets(.oneSet))
        var t = try Tournament.create(from: TournamentDraft(name: "Sets", configuration: config, players: Fixtures.players(4)), context: context)
        let match = try #require(t.currentRound?.matches.first).id
        for side in Array(repeating: TeamSide.a, count: 4) + [.a, .b] {
            try t.recordPoint(for: side, in: match, context: context)
        }
        let board = LiveBoardSnapshot(tournament: t, updatedAt: at)
        #expect(board.countsGames)
        let court = try #require(board.courts.first)
        #expect(court.state == .live)
        #expect(court.scoreA == "15" && court.scoreB == "15")
        #expect(court.sets == "1-0")
    }

    @Test("A finished playoff shows the champion and no courts")
    func champion() throws {
        let config = TournamentConfiguration(format: .americano, courtCount: 2, roundCount: 3, scoring: .totalPoints(24), seed: 4, playoff: .final)
        var t = try Tournament.create(from: TournamentDraft(name: "P", configuration: config, players: Fixtures.players(8)), context: context)
        var random = SeededGenerator(seed: 12)
        while let round = t.currentRound, round.kind != .knockout {
            try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        }
        let finalRound = try #require(t.currentRound)
        #expect(LiveBoardSnapshot(tournament: t, updatedAt: at).stage == .final)
        try t.enterResult(Score(a: 13, b: 12), for: finalRound.matches[0].id, context: context)
        t.finish(now: at)

        let board = LiveBoardSnapshot(tournament: t, updatedAt: at)
        #expect(board.status == .completed)
        #expect(board.courts.isEmpty && board.resting.isEmpty)
        #expect(board.round == 4 && board.rounds == 4)
        #expect(board.champion == t.sideName(finalRound.matches[0].sideA))
        #expect(board.runnerUp == t.sideName(finalRound.matches[0].sideB))
    }

    @Test("Compact JSON round-trips and uses the keys the web page reads")
    func json() throws {
        var t = try Fixtures.tournament(players: 8, courts: 2, rounds: 3, points: 16)
        let match = try #require(t.currentRound?.matches.first).id
        try t.recordPoint(for: .b, in: match, context: context)
        let board = LiveBoardSnapshot(tournament: t, updatedAt: at)
        let json = try board.json()
        #expect(try LiveBoardSnapshot.decode(json) == board)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(Set(object.keys) == ["v", "name", "format", "formatName", "status", "round", "rounds", "stage", "games", "standings", "courts", "resting", "updatedAt"])
        #expect(object["updatedAt"] as? String == "2027-01-15T08:10:00Z")
        let row = try #require((object["standings"] as? [[String: Any]])?.first)
        #expect(Set(row.keys) == ["rank", "tied", "name", "pts", "w", "d", "l", "diff"])
        let court = try #require((object["courts"] as? [[String: Any]])?.first)
        #expect(Set(court.keys) == ["court", "state", "a", "b", "sa", "sb"])
        #expect(court["sb"] as? String == "1")
        // Nothing but names and scores: no identifiers, devices or event history.
        #expect(!json.contains(t.players[0].id.rawValue.uuidString))
        #expect(!json.contains(t.id.rawValue.uuidString))
    }

    @Test("Tokens and links")
    func tokens() {
        #expect(LiveBoard.isValidToken("0123456789abcdefghijklMN"))
        #expect(!LiveBoard.isValidToken("short"))
        #expect(!LiveBoard.isValidToken("0123456789abcdefghijk-MN"))
        #expect(LiveBoard.url(token: "0123456789abcdefghijklMN").absoluteString == "https://wrexist.github.io/PadelOS/live/#0123456789abcdefghijklMN")
    }
}

@Suite("Spectator board token on the tournament")
struct LiveBoardTokenTests {
    let context = Fixtures.context()

    @Test("Tournaments saved before the spectator board existed still decode")
    func oldFilesDecode() throws {
        var t = try Fixtures.tournament(players: 8, courts: 2, rounds: 3)
        try t.setLiveBoardToken("0123456789abcdefghijklMN")
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(t)) as? [String: Any])
        #expect(object["liveBoardToken"] as? String == "0123456789abcdefghijklMN")
        object["liveBoardToken"] = nil
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Tournament.self, from: old)
        #expect(decoded.liveBoardToken == nil)
        #expect(decoded.liveBoardURL == nil)
        try t.setLiveBoardToken(nil)
        #expect(decoded == t)
    }

    @Test("Turning the board on does not count as a change to the tournament")
    func revisionUnchanged() throws {
        var t = try Fixtures.tournament(players: 8, courts: 2, rounds: 3)
        let revision = t.revision
        try t.setLiveBoardToken("0123456789abcdefghijklMN")
        #expect(t.revision == revision)
        #expect(t.liveBoardURL?.absoluteString == "https://wrexist.github.io/PadelOS/live/#0123456789abcdefghijklMN")
    }

    @Test("Guest copies never carry the organiser's board and cannot turn one on")
    func guests() throws {
        var host = try Fixtures.tournament(players: 8, courts: 2, rounds: 3)
        try host.setLiveBoardToken("0123456789abcdefghijklMN")
        var guest = Tournament.guestCopy(of: host, zoneName: "zone", zoneOwner: "owner")
        #expect(guest.liveBoardToken == nil)
        #expect(throws: TournamentError.self) { try guest.setLiveBoardToken("0123456789abcdefghijklMN") }

        let match = try #require(host.currentRound?.matches.first).id
        try host.recordPoint(for: .a, in: match, context: context)
        #expect(guest.rebase(onto: host, now: Fixtures.start) == .adopted(replayed: 0))
        #expect(guest.liveBoardToken == nil)
    }
}
