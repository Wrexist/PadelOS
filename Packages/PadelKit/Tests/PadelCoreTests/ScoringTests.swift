import Foundation
import Testing
@testable import PadelCore

@Suite("Scoring")
struct ScoringTests {
    let context = Fixtures.context()

    func firstMatch(_ t: Tournament) -> MatchID { t.rounds[0].matches[0].id }

    @Test("Points increment one side at a time and are persisted in the log")
    func increments() throws {
        var t = try Fixtures.tournament()
        let id = firstMatch(t)
        let event = try t.recordPoint(for: .a, in: id, context: context)
        try t.recordPoint(for: .b, in: id, context: context)
        try t.recordPoint(for: .a, in: id, context: context)
        let match = try #require(t.match(id))
        #expect(match.score == Score(a: 2, b: 1))
        #expect(match.status == .inProgress)
        #expect(match.log.count == 3)
        #expect(event.previousScore == .zero)
        #expect(event.resultingScore == Score(a: 1, b: 0))
        #expect(match.log[2].previousScore == Score(a: 1, b: 1))
    }

    @Test("A match cannot exceed its total and finishes exactly at the total")
    func totalLimit() throws {
        var t = try Fixtures.tournament(points: 16)
        let id = firstMatch(t)
        for _ in 0..<10 { try t.recordPoint(for: .a, in: id, context: context) }
        #expect(throws: TournamentError.scoring(.scoreIncomplete)) { try t.finishMatch(id, context: context) }
        for _ in 0..<6 { try t.recordPoint(for: .b, in: id, context: context) }
        #expect(ScoringEngine.isAwaitingConfirmation(t.match(id)!, rule: t.configuration.scoring))
        #expect(throws: TournamentError.scoring(.totalReached)) { try t.recordPoint(for: .a, in: id, context: context) }
        try t.finishMatch(id, context: context)
        #expect(t.match(id)?.status == .completed)
        #expect(t.match(id)?.score == Score(a: 10, b: 6))
        #expect(throws: TournamentError.scoring(.matchCompleted)) { try t.recordPoint(for: .b, in: id, context: context) }
    }

    @Test("An even total allows a draw")
    func draws() throws {
        var t = try Fixtures.tournament(points: 24)
        let id = firstMatch(t)
        try Fixtures.play(&t, id, a: 12, b: 12, context: context)
        #expect(t.match(id)?.score.winner == nil)
        let standings = StandingsCalculator.compute(t)
        let player = t.match(id)!.sideA.playerIDs[0]
        #expect(standings.entry(for: .player(player))?.draws == 1)
        #expect(standings.entry(for: .player(player))?.points == 12)
    }

    @Test("Undo reverses the last point, repeatedly, and then reports nothing to undo")
    func multipleUndo() throws {
        var t = try Fixtures.tournament()
        let id = firstMatch(t)
        try t.recordPoint(for: .a, in: id, context: context)
        try t.recordPoint(for: .b, in: id, context: context)
        try t.recordPoint(for: .b, in: id, context: context)
        try t.undoLastScoreChange(in: id, context: context)
        #expect(t.match(id)?.score == Score(a: 1, b: 1))
        try t.undoLastScoreChange(in: id, context: context)
        #expect(t.match(id)?.score == Score(a: 1, b: 0))
        try t.undoLastScoreChange(in: id, context: context)
        #expect(t.match(id)?.score == .zero)
        #expect(throws: TournamentError.scoring(.nothingToUndo)) { try t.undoLastScoreChange(in: id, context: context) }
        // The history is auditable: 3 points + 3 undos.
        #expect(t.match(id)?.log.count == 6)
        try t.recordPoint(for: .a, in: id, context: context)
        #expect(t.match(id)?.score == Score(a: 1, b: 0))
    }

    @Test("Undo of a score correction restores the previous score")
    func undoSetScore() throws {
        var t = try Fixtures.tournament()
        let id = firstMatch(t)
        try t.recordPoint(for: .a, in: id, context: context)
        try t.setScore(Score(a: 10, b: 5), in: id, context: context)
        try t.undoLastScoreChange(in: id, context: context)
        #expect(t.match(id)?.score == Score(a: 1, b: 0))
    }

    @Test("Undo is not possible on a finished match; reopen first")
    func undoAfterFinish() throws {
        var t = try Fixtures.tournament(points: 4)
        let id = firstMatch(t)
        try Fixtures.play(&t, id, a: 3, b: 1, context: context)
        #expect(throws: TournamentError.scoring(.matchCompleted)) { try t.undoLastScoreChange(in: id, context: context) }
        try t.reopenMatch(id, context: context)
        try t.undoLastScoreChange(in: id, context: context)
        #expect(t.match(id)?.score == Score(a: 3, b: 0))
        #expect(t.match(id)?.status == .inProgress)
    }

    @Test("Manual scores are validated against the rules")
    func setScoreValidation() throws {
        var t = try Fixtures.tournament(points: 24)
        let id = firstMatch(t)
        #expect(throws: TournamentError.scoring(.scoreExceedsRules)) { try t.setScore(Score(a: 20, b: 10), in: id, context: context) }
        #expect(throws: TournamentError.scoring(.scoreExceedsRules)) { try t.setScore(Score(a: -1, b: 10), in: id, context: context) }
        #expect(throws: TournamentError.scoring(.scoreIncomplete)) { try t.enterResult(Score(a: 10, b: 10), for: id, context: context) }
        try t.enterResult(Score(a: 15, b: 9), for: id, context: context)
        #expect(t.match(id)?.score == Score(a: 15, b: 9))
        #expect(t.match(id)?.isCompleted == true)
    }

    @Test("Correcting a finished result is recorded as reopen, set, finish and updates standings")
    func correction() throws {
        var t = try Fixtures.tournament(points: 24)
        let id = firstMatch(t)
        try t.enterResult(Score(a: 15, b: 9), for: id, context: context)
        let player = t.match(id)!.sideA.playerIDs[0]
        #expect(StandingsCalculator.compute(t).entry(for: .player(player))?.points == 15)
        try t.enterResult(Score(a: 9, b: 15), for: id, context: context)
        #expect(StandingsCalculator.compute(t).entry(for: .player(player))?.points == 9)
        let kinds = t.match(id)!.log.map(\.kind)
        #expect(kinds.suffix(3) == [.reopen, .setScore(Score(a: 9, b: 15)), .finish])
    }

    @Test("Timed matches accept any score and finish on demand")
    func timed() throws {
        let config = TournamentConfiguration(format: .americano, courtCount: 1, roundCount: 3, scoring: .timed(minutes: 12))
        var t = try Tournament.create(from: TournamentDraft(name: "T", configuration: config, players: Fixtures.players(4)), context: context)
        let id = firstMatch(t)
        for _ in 0..<30 { try t.recordPoint(for: .a, in: id, context: context) }
        try t.finishMatch(id, context: context)
        #expect(t.match(id)?.score == Score(a: 30, b: 0))
    }

    @Test("Replaying the log reproduces the cached state")
    func replayMatchesCache() throws {
        var t = try Fixtures.tournament()
        let id = firstMatch(t)
        var random = SeededGenerator(seed: 77)
        for _ in 0..<60 {
            switch random.nextInt(4) {
            case 0, 1: _ = try? t.recordPoint(for: .a, in: id, context: context)
            case 2: _ = try? t.recordPoint(for: .b, in: id, context: context)
            default: _ = try? t.undoLastScoreChange(in: id, context: context)
            }
            let match = t.match(id)!
            let replay = ScoringEngine.replay(match.log, rule: t.configuration.scoring)
            #expect(replay.score == match.score)
            #expect(replay.status == match.status)
        }
        var copy = t
        #expect(copy.repairCaches() == 0)
    }

    @Test("Applying the same event twice never double counts")
    func deduplication() throws {
        var t = try Fixtures.tournament()
        let id = firstMatch(t)
        var match = t.match(id)!
        let event = ScoreEvent(tournamentID: t.id, matchID: id, kind: .point(.a), timestamp: Fixtures.start, deviceID: DeviceID(), deviceSequence: 1, baseRevision: 0)
        #expect(ScoringEngine.apply(event, to: &match, rule: t.configuration.scoring) == .applied)
        #expect(ScoringEngine.apply(event, to: &match, rule: t.configuration.scoring) == .duplicate)
        #expect(match.score == Score(a: 1, b: 0))
        let report = t.applyRemoteEvents([event, event], context: context)
        #expect(report.applied == [event.id])
        #expect(report.duplicates == [event.id])
        #expect(t.match(id)?.score == Score(a: 1, b: 0))
        let again = t.applyRemoteEvents([event], context: context)
        #expect(again.duplicates == [event.id])
        #expect(t.match(id)?.score == Score(a: 1, b: 0))
    }

    @Test("Remote events are applied in per-device sequence order even when delivered out of order")
    func outOfOrderRemote() throws {
        var t = try Fixtures.tournament(points: 4)
        let id = firstMatch(t)
        let device = DeviceID()
        func event(_ kind: ScoreEvent.Kind, _ seq: Int) -> ScoreEvent {
            ScoreEvent(tournamentID: t.id, matchID: id, kind: kind, timestamp: Fixtures.start, deviceID: device, deviceSequence: seq, baseRevision: 0)
        }
        let p1 = event(.point(.a), 1), p2 = event(.point(.a), 2), u = event(.undo(p2.id), 3)
        let p3 = event(.point(.b), 4), p4 = event(.point(.b), 5), p5 = event(.point(.a), 6), f = event(.finish, 7)
        let report = t.applyRemoteEvents([f, p5, u, p1, p4, p2, p3], context: context)
        #expect(report.conflicts.isEmpty, "\(report.conflicts)")
        #expect(t.match(id)?.score == Score(a: 2, b: 2))
        #expect(t.match(id)?.isCompleted == true)
    }

    @Test("Conflicting remote events are kept for review, not discarded")
    func conflictsRecorded() throws {
        var t = try Fixtures.tournament(points: 4)
        let id = firstMatch(t)
        try t.enterResult(Score(a: 3, b: 1), for: id, context: context) // finished on the phone
        let watchPoint = ScoreEvent(tournamentID: t.id, matchID: id, kind: .point(.b), timestamp: Fixtures.start, deviceID: DeviceID(), deviceSequence: 1, baseRevision: 0)
        let report = t.applyRemoteEvents([watchPoint], context: context)
        #expect(report.conflicts.map(\.reason) == [.matchCompleted])
        #expect(t.match(id)?.score == Score(a: 3, b: 1))
        #expect(t.match(id)?.openConflicts.count == 1)
        #expect(t.openConflictCount == 1)
        #expect(t.contains(eventID: watchPoint.id))
        // Redelivery of a conflicting event is a duplicate, not a second conflict.
        let again = t.applyRemoteEvents([watchPoint], context: context)
        #expect(again.duplicates == [watchPoint.id])
        #expect(t.match(id)?.conflicts.count == 1)
        t.acknowledgeConflicts(in: id, now: Fixtures.start)
        #expect(t.openConflictCount == 0)
        #expect(t.match(id)?.conflicts.count == 1, "acknowledged, still auditable")
    }

    @Test("Events for a match that no longer exists are kept on the tournament")
    func orphanedEvents() throws {
        var t = try Fixtures.tournament()
        let event = ScoreEvent(tournamentID: t.id, matchID: MatchID(), kind: .point(.a), timestamp: Fixtures.start, deviceID: DeviceID(), deviceSequence: 1, baseRevision: 0)
        let report = t.applyRemoteEvents([event], context: context)
        #expect(report.conflicts.first?.reason == .unknownMatch)
        #expect(t.orphanedConflicts.count == 1)
        #expect(t.applyRemoteEvents([event], context: context).duplicates == [event.id])
    }

    @Test("Undo of a point that was superseded by a correction is rejected")
    func undoSuperseded() throws {
        var t = try Fixtures.tournament()
        let id = firstMatch(t)
        let point = try t.recordPoint(for: .a, in: id, context: context)
        try t.setScore(Score(a: 5, b: 5), in: id, context: context)
        var match = t.match(id)!
        let undo = ScoreEvent(tournamentID: t.id, matchID: id, kind: .undo(point.id), timestamp: Fixtures.start, deviceID: DeviceID(), deviceSequence: 1, baseRevision: 1)
        #expect(ScoringEngine.apply(undo, to: &match, rule: t.configuration.scoring) == .rejected(.undoSupersededByCorrection))
    }

    @Test("Scoring is blocked once the tournament is finished")
    func finishedTournamentIsReadOnly() throws {
        var t = try Fixtures.tournament()
        t.finish(now: Fixtures.start)
        #expect(throws: TournamentError.tournamentCompleted) { try t.recordPoint(for: .a, in: firstMatch(t), context: context) }
        t.reopen(context: context)
        try t.recordPoint(for: .a, in: firstMatch(t), context: context)
    }
}
