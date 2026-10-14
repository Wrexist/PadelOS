import Foundation
import Testing
@testable import PadelCore

@Suite("Live Activity content")
struct LiveMatchSummaryTests {
    let context = Fixtures.context()

    @Test("Rally scoring shows points, progress and a decided state")
    func points() throws {
        var t = try Fixtures.tournament(points: 4)
        let match = t.rounds[0].matches[0]
        var summary = try #require(LiveMatchSummary(tournament: t, matchID: match.id))
        #expect(summary.courtLabel == "Court 1")
        #expect(summary.roundLabel == "Round 1 of 7")
        #expect(summary.teamA == t.sideName(match.sideA))
        #expect(summary.scoreA == "0" && summary.detail == "0 of 4 points")
        #expect(summary.canScore)
        try Fixtures.play(&t, match.id, a: 3, b: 1, context: context)
        summary = try #require(LiveMatchSummary(tournament: t, matchID: match.id))
        #expect(summary.scoreA == "3" && summary.scoreB == "1")
        #expect(summary.isFinished && !summary.canScore)
        #expect(summary.detail == "Final")
        #expect(summary.progress == 1)
    }

    @Test("Games and sets show game points, games and the situation")
    func sets() throws {
        let config = TournamentConfiguration(format: .americano, courtCount: 1, roundCount: 3, scoring: .sets(.oneSet))
        var t = try Tournament.create(from: TournamentDraft(name: "S", configuration: config, players: Fixtures.players(4)), context: context)
        let id = t.rounds[0].matches[0].id
        for side in [TeamSide.a, .a, .a, .a, .a, .a, .a, .b, .b, .b] {
            try t.recordPoint(for: side, in: id, context: context)
        }
        let summary = try #require(LiveMatchSummary(tournament: t, matchID: id))
        #expect(summary.scoreA == "40" && summary.scoreB == "40")
        #expect(summary.detail == "Golden point · Games 1–0")
        #expect(summary.progress == nil)
    }

    @Test("Unknown match gives no summary")
    func unknown() throws {
        let t = try Fixtures.tournament()
        #expect(LiveMatchSummary(tournament: t, matchID: MatchID()) == nil)
    }
}
