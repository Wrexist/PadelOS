import Foundation
import Testing
@testable import PadelCore

@Suite("Validation")
struct ValidationTests {
    func codes(_ draft: TournamentDraft) -> Set<ValidationIssue.Code> {
        Set(ConfigurationValidator.validate(draft).map(\.code))
    }

    @Test("Too few players, empty and duplicate names are rejected with explanations")
    func players() {
        let config = TournamentConfiguration(format: .americano, courtCount: 1, roundCount: 3)
        #expect(codes(TournamentDraft(name: "X", configuration: config, players: Fixtures.players(3))).contains(.tooFewPlayers))
        var players = Fixtures.players(4)
        players[1].name = "  "
        #expect(codes(TournamentDraft(name: "X", configuration: config, players: players)).contains(.emptyPlayerName))
        players[1].name = "alex"
        let issues = ConfigurationValidator.validate(TournamentDraft(name: "X", configuration: config, players: players))
        let duplicate = issues.first { $0.code == .duplicatePlayerName }
        #expect(duplicate?.suggestion != nil)
        players[1] = players[0]
        #expect(codes(TournamentDraft(name: "X", configuration: config, players: players)).contains(.duplicatePlayerID))
        #expect(codes(TournamentDraft(name: " ", configuration: config, players: Fixtures.players(4))).contains(.missingName))
    }

    @Test("Unusable courts produce a warning with a valid alternative, never a silent change")
    func capacity() {
        let config = TournamentConfiguration(format: .americano, courtCount: 3, roundCount: 3)
        let issues = ConfigurationValidator.validate(TournamentDraft(name: "X", configuration: config, players: Fixtures.players(9)))
        let warning = issues.first { $0.code == .unusedCourts }
        #expect(warning?.severity == .warning)
        #expect(warning?.message == "Only 2 of 3 courts can be used with these players.")
        #expect(ConfigurationValidator.errors(TournamentDraft(name: "X", configuration: config, players: Fixtures.players(9))).isEmpty)
    }

    @Test("Mixed constraints must be satisfiable")
    func mixed() {
        let config = TournamentConfiguration(format: .mixedAmericano, courtCount: 2, roundCount: 3)
        #expect(codes(TournamentDraft(name: "X", configuration: config, players: Fixtures.mixedPlayers(a: 5, b: 1))).contains(.groupTooSmall))
        var players = Fixtures.mixedPlayers(a: 2, b: 2)
        players[0].group = nil
        #expect(codes(TournamentDraft(name: "X", configuration: config, players: players)).contains(.missingGroup))
        let uneven = ConfigurationValidator.validate(TournamentDraft(name: "X", configuration: config, players: Fixtures.mixedPlayers(a: 6, b: 4)))
        #expect(uneven.contains { $0.code == .unevenGroups && $0.severity == .warning })
    }

    @Test("Teams need two distinct players and a player can be in only one team")
    func teams() {
        let config = TournamentConfiguration(format: .teamAmericano, courtCount: 1, roundCount: 3)
        var fixture = Fixtures.teams(3)
        #expect(ConfigurationValidator.errors(TournamentDraft(name: "X", configuration: config, players: fixture.players, teams: fixture.teams)).isEmpty)
        fixture.teams[1].playerIDs[0] = fixture.teams[0].playerIDs[0]
        #expect(codes(TournamentDraft(name: "X", configuration: config, players: fixture.players, teams: fixture.teams)).contains(.playerInTwoTeams))
        fixture.teams[2].playerIDs = [fixture.teams[2].playerIDs[0]]
        #expect(codes(TournamentDraft(name: "X", configuration: config, players: fixture.players, teams: fixture.teams)).contains(.invalidTeam))
        let one = Fixtures.teams(1)
        #expect(codes(TournamentDraft(name: "X", configuration: config, players: one.players, teams: one.teams)).contains(.tooFewTeams))
    }

    @Test("Points, rounds and courts are range-checked")
    func ranges() {
        let players = Fixtures.players(4)
        func codesFor(_ config: TournamentConfiguration) -> Set<ValidationIssue.Code> { codes(TournamentDraft(name: "X", configuration: config, players: players)) }
        #expect(codesFor(TournamentConfiguration(scoring: .totalPoints(2))).contains(.invalidPoints))
        #expect(codesFor(TournamentConfiguration(roundCount: 0)).contains(.invalidRoundCount))
        #expect(codesFor(TournamentConfiguration(courtCount: 0)).contains(.invalidCourtCount))
        #expect(codesFor(TournamentConfiguration(roundCount: 1, standingsBasedFinalRound: true)).contains(.finalRoundNeedsMoreRounds))
        #expect(codesFor(TournamentConfiguration(scoring: .timed(minutes: 12), restCompensation: .halfMatchTotal)).contains(.restCompensationNeedsTotalPoints))
    }

    @Test("Creating with an invalid configuration throws and explains")
    func createThrows() {
        let draft = TournamentDraft(name: "X", configuration: TournamentConfiguration(), players: Fixtures.players(2))
        #expect(throws: TournamentError.self) { try Tournament.create(from: draft, context: Fixtures.context()) }
    }

    @Test("Round planner suggests a full rotation that fits the evening")
    func roundPlanner() {
        #expect(RoundPlanner.fullRotationRounds(format: .americano, players: Fixtures.players(8), teamCount: 0, courts: 2) == 7)
        #expect(RoundPlanner.fullRotationRounds(format: .americano, players: Fixtures.players(5), teamCount: 0, courts: 1) == 5)
        #expect(RoundPlanner.fullRotationRounds(format: .teamAmericano, players: [], teamCount: 6, courts: 3) == 5)
        let recommended = RoundPlanner.recommendedRounds(format: .americano, players: Fixtures.players(16), teamCount: 0, courts: 4, scoring: .totalPoints(24), availableMinutes: 120)
        #expect(recommended >= 1 && recommended <= 15)
    }
}

@Suite("Tournament management")
struct LifecycleTests {
    let context = Fixtures.context()

    @Test("Withdrawing a player keeps completed rounds and reschedules the rest without them")
    func withdrawal() throws {
        var t = try Fixtures.tournament(players: 9, courts: 2, rounds: 6)
        var random = SeededGenerator(seed: 1)
        try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        let played = t.rounds[0]
        let leaver = played.matches[0].sideA.playerIDs[0]
        try t.withdrawPlayer(leaver, context: context)
        #expect(t.rounds[0] == played)
        #expect(t.rounds.count == 6)
        for round in t.rounds.dropFirst() {
            #expect(!round.matches.flatMap(\.allPlayerIDs).contains(leaver))
            #expect(!round.restingPlayerIDs.contains(leaver))
        }
        #expect(Invariants.check(t).isEmpty, "\(Invariants.check(t))")
        // 8 remaining players, 2 courts: nobody rests any more.
        #expect(t.rounds.dropFirst().allSatisfy { $0.restingPlayerIDs.isEmpty })
    }

    @Test("A withdrawal that would break the format is refused")
    func refusedWithdrawal() throws {
        var t = try Fixtures.tournament(players: 4, courts: 1, rounds: 3)
        #expect(throws: TournamentError.self) { try t.withdrawPlayer(t.players[0].id, context: context) }
        var mixed = try Fixtures.tournament(format: .mixedAmericano, players: 4, courts: 1, rounds: 3)
        #expect(throws: TournamentError.self) { try mixed.withdrawPlayer(mixed.players[0].id, context: context) }
    }

    @Test("Adding a late player schedules them in future rounds and does not make them rest first")
    func lateJoiner() throws {
        var t = try Fixtures.tournament(players: 8, courts: 2, rounds: 6)
        var random = SeededGenerator(seed: 1)
        try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        let newcomer = try t.addPlayer(name: "Zoe", context: context)
        #expect(Invariants.check(t).isEmpty, "\(Invariants.check(t))")
        #expect(!t.rounds[2].restingPlayerIDs.contains(newcomer.id))
        #expect(throws: TournamentError.self) { try t.addPlayer(name: "zoe", context: context) }
    }

    @Test("Withdrawing a team in Team Americano")
    func teamWithdrawal() throws {
        var t = try Fixtures.tournament(format: .teamAmericano, players: 5, courts: 2, rounds: 5)
        let team = t.teams[0].id
        try t.withdrawTeam(team, context: context)
        #expect(t.rounds.allSatisfy { !$0.matches.contains { $0.sideA.teamID == team || $0.sideB.teamID == team } })
        _ = try t.addTeam(name: "Late Team", playerNames: ["Q", "R"], context: context)
        #expect(Invariants.check(t).isEmpty)
    }

    @Test("Changing courts or rounds rebuilds only rounds that have not started")
    func editSettings() throws {
        var t = try Fixtures.tournament(players: 12, courts: 3, rounds: 6)
        try t.recordPoint(for: .a, in: t.rounds[0].matches[0].id, context: context)
        let started = t.rounds[0]
        try t.updateSettings(courtCount: 2, context: context)
        #expect(t.rounds[0] == started)
        #expect(t.rounds.dropFirst().allSatisfy { $0.matches.count == 2 })
        try t.updateSettings(roundCount: 8, context: context)
        #expect(t.rounds.count == 8)
        #expect(throws: TournamentError.self) { try t.updateSettings(scoring: .totalPoints(32), context: context) }
        #expect(throws: TournamentError.self) { try t.updateSettings(roundCount: 0, context: context) }
        #expect(Invariants.check(t).isEmpty)
    }

    @Test("Points rule can change before play starts")
    func editPointsBeforeStart() throws {
        var t = try Fixtures.tournament()
        try t.updateSettings(scoring: .totalPoints(32), context: context)
        #expect(t.configuration.scoring == .totalPoints(32))
    }

    @Test("Restart clears every result and rebuilds the same schedule for the same seed")
    func restart() throws {
        let fresh = try Fixtures.tournament(players: 8)
        var t = fresh
        var random = SeededGenerator(seed: 1)
        try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        t.restart(context: Fixtures.context())
        #expect(!t.hasAnyResult)
        #expect(t.rounds.map { $0.matches.map(\.allPlayerIDs) } == fresh.rounds.map { $0.matches.map(\.allPlayerIDs) })
        t.restart(newSeed: 999, context: context)
        #expect(t.rounds.map { $0.matches.map(\.allPlayerIDs) } != fresh.rounds.map { $0.matches.map(\.allPlayerIDs) })
    }

    @Test("Finish and reopen")
    func finishReopen() throws {
        var t = try Fixtures.tournament()
        let revision = t.revision
        t.finish(now: Fixtures.start)
        #expect(t.status == .completed)
        #expect(t.revision == revision + 1)
        t.reopen(context: context)
        #expect(t.status == .active)
    }

    @Test("Every mutation increments the revision")
    func revisionMonotonic() throws {
        var t = try Fixtures.tournament()
        var last = t.revision
        let id = t.rounds[0].matches[0].id
        try t.recordPoint(for: .a, in: id, context: context)
        #expect(t.revision > last); last = t.revision
        try t.undoLastScoreChange(in: id, context: context)
        #expect(t.revision > last); last = t.revision
        try t.rename("New", now: Fixtures.start)
        #expect(t.revision > last)
    }

    @Test("Watch projection strips history from finished earlier rounds only")
    func projection() throws {
        var t = try Fixtures.tournament(points: 4)
        var random = SeededGenerator(seed: 1)
        try Fixtures.completeCurrentRound(&t, random: &random, context: context)
        try t.recordPoint(for: .a, in: t.rounds[1].matches[0].id, context: context)
        let compact = t.compactedForWatch()
        #expect(compact.rounds[0].matches.allSatisfy { $0.isLogCompacted && $0.log.isEmpty })
        #expect(compact.rounds[0].matches.map(\.score) == t.rounds[0].matches.map(\.score))
        #expect(compact.rounds[1].matches[0].log.count == 1)
        var copy = compact
        let event = ScoreEvent(tournamentID: t.id, matchID: t.rounds[0].matches[0].id, kind: .reopen, timestamp: Fixtures.start, deviceID: DeviceID(), deviceSequence: 1, baseRevision: 0)
        #expect(copy.applyProvisional(event) == .rejected(.matchNotEditable))
    }

    @Test("Tournaments survive an encode/decode round trip unchanged")
    func codableRoundTrip() throws {
        for format in TournamentFormat.allCases {
            var t = try Fixtures.tournament(format: format, players: format == .teamAmericano ? 4 : 8, courts: 2, rounds: 3, finalRound: true)
            var random = SeededGenerator(seed: 1)
            try Fixtures.completeCurrentRound(&t, random: &random, context: context)
            let data = try JSONEncoder().encode(t)
            #expect(try JSONDecoder().decode(Tournament.self, from: data) == t)
        }
    }
}
