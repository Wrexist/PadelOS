import Foundation
import Testing
@testable import PadelCore

/// Smallest possible number of partner repeats: every partnership slot beyond the number
/// of distinct possible partnerships must be a repeat.
private func unavoidablePartnerRepeats(players: Int, courts: Int, rounds: Int) -> Int {
    let matches = min(courts, players / 4)
    let slots = 2 * matches * rounds
    return max(0, slots - players * (players - 1) / 2)
}

@Suite("Scheduling")
struct SchedulingTests {
    struct Case: CustomTestStringConvertible, Sendable {
        var players: Int
        var courts: Int
        var rounds: Int
        var testDescription: String { "\(players) players, \(courts) courts, \(rounds) rounds" }
    }

    static let americanoCases: [Case] = [
        Case(players: 4, courts: 1, rounds: 3),
        Case(players: 5, courts: 1, rounds: 5),
        Case(players: 6, courts: 1, rounds: 8),
        Case(players: 7, courts: 1, rounds: 7),
        Case(players: 8, courts: 2, rounds: 7),
        Case(players: 9, courts: 2, rounds: 9),
        Case(players: 10, courts: 2, rounds: 12),
        Case(players: 12, courts: 3, rounds: 11),
        Case(players: 12, courts: 2, rounds: 8),   // more players than court capacity
        Case(players: 13, courts: 3, rounds: 8),   // odd count
        Case(players: 16, courts: 4, rounds: 15),
        Case(players: 24, courts: 6, rounds: 10),  // large supported tournament
    ]

    @Test("Americano rounds are valid, fair and avoid repeated partners", arguments: americanoCases)
    func americanoQuality(_ c: Case) throws {
        let t = try Fixtures.tournament(format: .americano, players: c.players, courts: c.courts, rounds: c.rounds)
        #expect(t.rounds.count == c.rounds)
        #expect(Invariants.check(t).isEmpty, "\(Invariants.check(t))")
        let metrics = ScheduleMetrics.of(t)
        let lowerBound = unavoidablePartnerRepeats(players: c.players, courts: c.courts, rounds: c.rounds)
        // The heuristic must reach the theoretical minimum on every supported reference case.
        #expect(metrics.partnerRepeats == lowerBound, "partner repeats \(metrics.partnerRepeats), minimum \(lowerBound)")
        #expect(metrics.playedSpread <= 1, "played spread \(metrics.playedSpread)")
        #expect(metrics.restSpread <= 1)
        #expect(metrics.consecutiveRests == 0)
        // Each court is used whenever enough players exist.
        let expectedMatches = min(c.courts, c.players / 4)
        #expect(t.rounds.allSatisfy { $0.matches.count == expectedMatches })
    }

    @Test("Eight players over seven rounds: every pair partners once and opposes twice")
    func eightPlayerWhist() throws {
        let t = try Fixtures.tournament(format: .americano, players: 8, courts: 2, rounds: 7)
        let history = PlayerHistory.players(from: t.rounds)
        let ids = t.players.map(\.id)
        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                #expect(history.partners[ids[i], ids[j]] == 1)
                #expect(history.opponents[ids[i], ids[j]] == 2)
            }
        }
    }

    @Test("Same configuration and seed produce the identical schedule")
    func reproducible() throws {
        for format in TournamentFormat.allCases {
            let a = try Fixtures.tournament(format: format, players: format.usesTeams ? 6 : 10, courts: 2, rounds: 6, seed: 42)
            let b = try Fixtures.tournament(format: format, players: format.usesTeams ? 6 : 10, courts: 2, rounds: 6, seed: 42)
            #expect(a == b, "\(format) not reproducible")
        }
    }

    @Test("A different seed gives a different draw")
    func seedChangesDraw() throws {
        let a = try Fixtures.tournament(format: .americano, players: 8, courts: 2, rounds: 7, seed: 1)
        let b = try Fixtures.tournament(format: .americano, players: 8, courts: 2, rounds: 7, seed: 2)
        let pairsA = a.rounds.map { $0.matches.map { Set($0.allPlayerIDs) } }
        let pairsB = b.rounds.map { $0.matches.map { Set($0.allPlayerIDs) } }
        #expect(pairsA != pairsB)
    }

    @Test("Mixed Americano: one player from each group per team, partners never repeat when avoidable")
    func mixedQuality() throws {
        for (a, b, courts, rounds) in [(4, 4, 2, 4), (6, 6, 3, 6), (8, 8, 4, 8), (6, 4, 2, 6), (5, 7, 2, 6)] {
            let config = TournamentConfiguration(format: .mixedAmericano, courtCount: courts, roundCount: rounds, seed: 3)
            let t = try Tournament.create(from: TournamentDraft(name: "Mixed", configuration: config, players: Fixtures.mixedPlayers(a: a, b: b)), context: Fixtures.context())
            #expect(Invariants.check(t).isEmpty, "\(Invariants.check(t))")
            let metrics = ScheduleMetrics.of(t)
            let slots = 2 * min(courts, a / 2, b / 2) * rounds
            #expect(metrics.partnerRepeats == max(0, slots - a * b), "\(a)+\(b): \(metrics.partnerRepeats) repeats")
            // Rest fairness is per group.
            let history = PlayerHistory.players(from: t.rounds)
            for group in PlayerGroup.allCases {
                let played = t.players.filter { $0.group == group }.map { history.playedCount($0.id) }
                #expect((played.max() ?? 0) - (played.min() ?? 0) <= 1)
            }
        }
    }

    @Test("Team Americano: full round robin before any pairing repeats", arguments: [(4, 2, 3), (5, 2, 5), (6, 3, 5), (6, 2, 7), (7, 2, 10), (8, 4, 7), (8, 2, 14), (10, 3, 15)])
    func teamRoundRobin(teams: Int, courts: Int, rounds: Int) throws {
        let t = try Fixtures.tournament(format: .teamAmericano, players: teams, courts: courts, rounds: rounds)
        #expect(Invariants.check(t).isEmpty, "\(Invariants.check(t))")
        let metrics = ScheduleMetrics.of(t)
        let matches = t.rounds.reduce(0) { $0 + $1.matches.count }
        let pairings = teams * (teams - 1) / 2
        #expect(metrics.opponentRepeats == max(0, matches - pairings))
        #expect(metrics.playedSpread <= 1)
    }

    @Test("Randomised configurations always satisfy the hard constraints (seed 2026)")
    func randomisedInvariants() throws {
        var random = SeededGenerator(seed: 2026)
        for iteration in 0..<40 {
            let format = TournamentFormat.allCases[random.nextInt(TournamentFormat.allCases.count)]
            let courts = 1 + random.nextInt(4)
            let rounds = 1 + random.nextInt(9)
            let count = format.usesTeams ? 2 + random.nextInt(9) : 4 + random.nextInt(17)
            let seed = random.next()
            let t = try Fixtures.tournament(format: format, players: count, courts: courts, rounds: rounds, seed: seed)
            let problems = Invariants.check(t)
            #expect(problems.isEmpty, "iteration \(iteration) \(format) n=\(count) c=\(courts) r=\(rounds) seed=\(seed): \(problems)")
            // Rest fairness is guaranteed per group for Mixed (uneven groups rest at different
            // rates by design) and across everyone otherwise.
            let history = PlayerHistory.players(from: t.rounds)
            let groups: [[Player]] = format.usesGroups
                ? PlayerGroup.allCases.map { g in t.players.filter { $0.group == g } }
                : [t.players]
            for group in groups where !format.usesTeams {
                let played = group.map { history.playedCount($0.id) }
                #expect((played.max() ?? 0) - (played.min() ?? 0) <= 1, "iteration \(iteration) \(format) n=\(count) c=\(courts) r=\(rounds) seed=\(seed)")
            }
            if format.usesTeams {
                #expect(ScheduleMetrics.of(t).playedSpread <= 1, "iteration \(iteration) seed=\(seed)")
            }
        }
    }

    @Test("A typical schedule is generated quickly")
    func performance() throws {
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            _ = try Fixtures.tournament(format: .americano, players: 16, courts: 4, rounds: 10)
        }
        // Debug builds are ~10× slower than release; keep a generous bound.
        #expect(elapsed < .seconds(10))
    }
}
