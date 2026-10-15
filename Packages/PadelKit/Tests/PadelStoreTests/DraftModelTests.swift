import Foundation
import Testing
@testable import PadelCore
@testable import PadelStore

@Suite("Create tournament form")
@MainActor
struct DraftModelTests {
    let monday = Date(timeIntervalSince1970: 1_800_000_000) // a Friday in UTC? name is derived, just check suffix

    @Test("Adding players trims names and refuses duplicates and blanks")
    func addPlayers() {
        let model = TournamentDraftModel(seed: 1)
        #expect(model.addPlayer(named: "  Alex ") == .added)
        #expect(model.addPlayer(named: "alex") == .duplicate("alex"))
        #expect(model.addPlayer(named: "   ") == .empty)
        #expect(model.players.map(\.name) == ["Alex"])
    }

    @Test("Pasting a list adds every new name and reports duplicates")
    func pasteMultiple() {
        let model = TournamentDraftModel(seed: 1)
        model.addPlayer(named: "Alex")
        let result = model.addMultiple("1. Lisa\n2) Johan, Maja; alex\n- Erik\n• Sofia\n\n")
        #expect(result.added == 5)
        #expect(result.skipped == ["alex"])
        #expect(model.players.map(\.name) == ["Alex", "Lisa", "Johan", "Maja", "Erik", "Sofia"])
    }

    @Test("Default draft with eight players is valid and recommends a full rotation")
    func validDefault() throws {
        let model = TournamentDraftModel(seed: 1)
        model.addMultiple("A,B,C,D,E,F,G,H")
        #expect(model.canCreate)
        #expect(model.fullRotationRounds == 7)
        #expect(model.recommendedRounds >= 1 && model.recommendedRounds <= 7)
        let t = try Tournament.create(from: model.draft, context: EngineContext(now: Date(), deviceID: DeviceID()))
        #expect(t.rounds.count == model.roundCount)
    }

    @Test("Team Americano pairs players in order and flags a missing partner")
    func teams() throws {
        let model = TournamentDraftModel(seed: 1)
        model.format = .teamAmericano
        model.addMultiple("Alex, Johan, Lisa, Maja, Erik")
        #expect(model.teams.map(\.name) == ["Alex & Johan", "Lisa & Maja"])
        #expect(model.hasUnpairedPlayer)
        #expect(!model.canCreate)
        #expect(model.errors.first?.message == "Erik has no partner yet.")
        model.addPlayer(named: "Sofia")
        #expect(model.canCreate)
        #expect(model.teams == model.teams, "team IDs are stable between reads")
        let t = try Tournament.create(from: model.draft, context: EngineContext(now: Date(), deviceID: DeviceID()))
        #expect(t.teams.count == 3)
    }

    @Test("Mixed Americano uses the preselected group and validates both groups")
    func mixed() {
        let model = TournamentDraftModel(seed: 1)
        model.format = .mixedAmericano
        model.nextGroup = .a
        model.addMultiple("A1, A2")
        #expect(model.needsMorePlayers)
        model.nextGroup = .b
        model.addMultiple("B1, B2")
        #expect(!model.needsMorePlayers)
        #expect(model.canCreate)
        model.setGroup(.a, for: model.players[3].id)
        #expect(!model.canCreate)
    }

    @Test("Reordering players")
    func move() {
        let model = TournamentDraftModel(seed: 1)
        model.addMultiple("A, B, C, D")
        model.movePlayers(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(model.players.map(\.name) == ["B", "C", "A", "D"])
    }

    @Test("Quick Americano reuses recent players and defaults")
    func quickStart() {
        var settings = AppSettings()
        settings.defaultCourtCount = 1
        settings.rememberNames(["Alex", "Lisa", "Johan", "Maja", "Erik"])
        let model = TournamentDraftModel.quickAmericano(settings: settings)
        #expect(model.format == .americano)
        #expect(model.players.count == 4)
        #expect(model.name.hasPrefix("Americano "))
        #expect(model.suggestions(from: settings.recentPlayerNames) == ["Erik"])
    }

    @Test("Timed matches disable rest points")
    func timed() {
        let model = TournamentDraftModel(seed: 1)
        model.addMultiple("A,B,C,D,E")
        model.restCompensation = .halfMatchTotal
        model.isTimed = true
        #expect(model.configuration.restCompensation == .none)
        #expect(model.canCreate)
    }
}
