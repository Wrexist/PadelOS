import AppIntents
import Foundation

/// +1 from the Lock Screen or Dynamic Island. `LiveActivityIntent` runs in the app's
/// process, so the point goes through the same store transaction as an in-app tap. The
/// widget extension compiles this type only to draw the button (`WIDGET_EXTENSION`).
struct RecordPointIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Record Point"
    static let isDiscoverable = false

    @Parameter(title: "Tournament") var tournamentID: String
    @Parameter(title: "Match") var matchID: String
    /// "a" or "b".
    @Parameter(title: "Side") var side: String

    init() {}

    init(tournamentID: String, matchID: String, side: String) {
        self.tournamentID = tournamentID
        self.matchID = matchID
        self.side = side
    }

    #if WIDGET_EXTENSION
    func perform() async throws -> some IntentResult { .result() }
    #else
    @MainActor
    func perform() async throws -> some IntentResult {
        await LiveActivityActions.recordPoint(tournamentID: tournamentID, matchID: matchID, side: side)
        return .result()
    }
    #endif
}

/// Undo the last point from the Lock Screen.
struct UndoPointIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Undo Point"
    static let isDiscoverable = false

    @Parameter(title: "Tournament") var tournamentID: String
    @Parameter(title: "Match") var matchID: String

    init() {}

    init(tournamentID: String, matchID: String) {
        self.tournamentID = tournamentID
        self.matchID = matchID
    }

    #if WIDGET_EXTENSION
    func perform() async throws -> some IntentResult { .result() }
    #else
    @MainActor
    func perform() async throws -> some IntentResult {
        await LiveActivityActions.undo(tournamentID: tournamentID, matchID: matchID)
        return .result()
    }
    #endif
}
