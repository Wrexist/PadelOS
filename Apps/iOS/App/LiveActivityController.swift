import ActivityKit
import Foundation
import PadelCore
import PadelStore

/// Starts, updates and ends the match Live Activity. Driven by store changes, so points
/// from the app, the Lock Screen and the Apple Watch all appear on the Lock Screen.
@MainActor
final class LiveActivityController {
    private let store: TournamentStore
    private let isEnabled: () -> Bool

    init(store: TournamentStore, isEnabled: @escaping () -> Bool) {
        self.store = store
        self.isEnabled = isEnabled
    }

    var areActivitiesAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private var activities: [Activity<MatchActivityAttributes>] {
        Activity<MatchActivityAttributes>.activities
    }

    /// Shows the match on the Lock Screen. Any activity for another match is ended, so
    /// there is never more than one.
    func start(tournamentID: TournamentID, matchID: MatchID) {
        guard isEnabled(), areActivitiesAvailable,
              let tournament = store.tournament(tournamentID),
              let summary = LiveMatchSummary(tournament: tournament, matchID: matchID),
              !summary.isFinished else { return }
        let matchKey = matchID.rawValue.uuidString
        if activities.contains(where: { $0.attributes.matchID == matchKey && $0.activityState == .active }) { return }
        for activity in activities where activity.attributes.matchID != matchKey {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        let attributes = MatchActivityAttributes(
            tournamentID: tournamentID.rawValue.uuidString,
            matchID: matchKey,
            tournamentName: summary.tournamentName,
            courtLabel: summary.courtLabel,
            roundLabel: summary.roundLabel,
            teamA: summary.teamA,
            teamB: summary.teamB
        )
        do {
            _ = try Activity.request(attributes: attributes, content: ActivityContent(state: Self.state(summary), staleDate: nil), pushType: nil)
        } catch {
            // Live Activities are optional: scoring never depends on them.
        }
    }

    /// Pushes the latest score to every running activity and ends finished ones.
    func refresh() async {
        for activity in activities where activity.activityState == .active {
            guard let tournamentID = TournamentID(uuidString: activity.attributes.tournamentID),
                  let matchID = MatchID(uuidString: activity.attributes.matchID),
                  let tournament = store.tournament(tournamentID),
                  let summary = LiveMatchSummary(tournament: tournament, matchID: matchID) else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            let content = ActivityContent(state: Self.state(summary), staleDate: nil)
            if summary.isFinished {
                await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
            } else if content.state != activity.content.state {
                await activity.update(content)
            }
        }
    }

    func endAll() async {
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func state(_ summary: LiveMatchSummary) -> MatchActivityAttributes.ContentState {
        MatchActivityAttributes.ContentState(
            scoreA: summary.scoreA,
            scoreB: summary.scoreB,
            detail: summary.detail,
            progress: summary.progress,
            canScore: summary.canScore,
            isFinished: summary.isFinished
        )
    }
}

/// Entry points for the Lock Screen buttons (see `RecordPointIntent`).
@MainActor
enum LiveActivityActions {
    static func recordPoint(tournamentID: String, matchID: String, side: String) async {
        let model = AppModel.shared
        model.start()
        guard let t = TournamentID(uuidString: tournamentID), let m = MatchID(uuidString: matchID) else { return }
        try? model.store.recordPoint(side == "b" ? .b : .a, match: m, in: t)
        await model.liveActivities.refresh()
    }

    static func undo(tournamentID: String, matchID: String) async {
        let model = AppModel.shared
        model.start()
        guard let t = TournamentID(uuidString: tournamentID), let m = MatchID(uuidString: matchID) else { return }
        try? model.store.undo(match: m, in: t)
        await model.liveActivities.refresh()
    }
}
