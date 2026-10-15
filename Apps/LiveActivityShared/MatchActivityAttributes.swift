import ActivityKit
import Foundation

/// Live Activity for the match being scored on the iPhone. Shared by the app (which
/// starts and updates it) and the widget extension (which draws it).
struct MatchActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Big figures: points, or game points (15, 30, 40, Ad) for games and sets.
        var scoreA: String
        var scoreB: String
        var detail: String
        var progress: Double?
        var canScore: Bool
        var isFinished: Bool
    }

    var tournamentID: String
    var matchID: String
    var tournamentName: String
    var courtLabel: String
    var roundLabel: String
    var teamA: String
    var teamB: String

    /// Opens the match in the app when the activity is tapped.
    var deepLink: URL? {
        URL(string: "padelos://match/\(tournamentID)/\(matchID)")
    }
}
