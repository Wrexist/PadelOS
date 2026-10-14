import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct PadelOSWidgets: WidgetBundle {
    var body: some Widget {
        MatchLiveActivity()
    }
}

/// Palette for the Live Activity. The extension does not share the app's design-system
/// file, so the few tokens it needs are repeated here (same values as `Theme`).
private enum LiveColors {
    static let graphite = Color(red: 0x10 / 255, green: 0x12 / 255, blue: 0x10 / 255)
    static let lime = Color(red: 0xC7 / 255, green: 0xF3 / 255, blue: 0x6B / 255)
    static let muted = Color(red: 0x8B / 255, green: 0x92 / 255, blue: 0x8A / 255)
    static let raised = Color(red: 0x25 / 255, green: 0x29 / 255, blue: 0x25 / 255)
}

struct MatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchActivityAttributes.self) { context in
            LockScreenMatchView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(LiveColors.graphite)
                .activitySystemActionForegroundColor(LiveColors.lime)
                .widgetURL(context.attributes.deepLink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TeamColumn(name: context.attributes.teamA, score: context.state.scoreA, highlight: true, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TeamColumn(name: context.attributes.teamB, score: context.state.scoreB, highlight: false, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.attributes.courtLabel) · \(context.state.detail)")
                        .font(.caption2)
                        .foregroundStyle(LiveColors.muted)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ScoreButtons(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                Text(context.state.scoreA)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(LiveColors.lime)
            } compactTrailing: {
                Text(context.state.scoreB)
                    .font(.headline.monospacedDigit())
            } minimal: {
                Text("\(context.state.scoreA)-\(context.state.scoreB)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(LiveColors.lime)
            }
            .widgetURL(context.attributes.deepLink)
            .keylineTint(LiveColors.lime)
        }
    }
}

struct LockScreenMatchView: View {
    let attributes: MatchActivityAttributes
    let state: MatchActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(attributes.courtLabel) · \(attributes.roundLabel)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiveColors.lime)
                Spacer()
                Text(attributes.tournamentName)
                    .font(.caption)
                    .foregroundStyle(LiveColors.muted)
                    .lineLimit(1)
            }
            HStack(alignment: .center) {
                TeamColumn(name: attributes.teamA, score: state.scoreA, highlight: true, alignment: .leading)
                Spacer()
                Text("–").font(.title2).foregroundStyle(LiveColors.muted)
                Spacer()
                TeamColumn(name: attributes.teamB, score: state.scoreB, highlight: false, alignment: .trailing)
            }
            if let progress = state.progress, !state.isFinished {
                ProgressView(value: progress)
                    .tint(LiveColors.lime)
            }
            HStack {
                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(LiveColors.muted)
                    .lineLimit(1)
                Spacer()
            }
            ScoreButtons(attributes: attributes, state: state)
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}

struct TeamColumn: View {
    let name: String
    let score: String
    let highlight: Bool
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(score)
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(highlight ? LiveColors.lime : .white)
                .contentTransition(.numericText())
            Text(name)
                .font(.caption)
                .foregroundStyle(LiveColors.muted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// +1 Team A, Undo, +1 Team B. Hidden once the match is decided or finished.
struct ScoreButtons: View {
    let attributes: MatchActivityAttributes
    let state: MatchActivityAttributes.ContentState

    var body: some View {
        if state.canScore {
            HStack(spacing: 8) {
                Button(intent: RecordPointIntent(tournamentID: attributes.tournamentID, matchID: attributes.matchID, side: "a")) {
                    Text("+1 A").frame(maxWidth: .infinity)
                }
                .tint(LiveColors.lime)
                .foregroundStyle(LiveColors.graphite)
                .accessibilityLabel("Point for \(attributes.teamA)")
                Button(intent: UndoPointIntent(tournamentID: attributes.tournamentID, matchID: attributes.matchID)) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .tint(LiveColors.raised)
                .accessibilityLabel("Undo last point")
                Button(intent: RecordPointIntent(tournamentID: attributes.tournamentID, matchID: attributes.matchID, side: "b")) {
                    Text("+1 B").frame(maxWidth: .infinity)
                }
                .tint(LiveColors.raised)
                .accessibilityLabel("Point for \(attributes.teamB)")
            }
            .buttonStyle(.borderedProminent)
            .font(.subheadline.weight(.bold))
        } else if !state.isFinished {
            Text("Open PadelOS to confirm the result")
                .font(.caption)
                .foregroundStyle(LiveColors.muted)
        }
    }
}
