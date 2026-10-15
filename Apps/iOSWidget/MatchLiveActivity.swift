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

/// The match on the Lock Screen and in the Dynamic Island: a night-court scoreboard with
/// big tabular numerals that roll on every point, a progress rail with the ball at its
/// head, and +1 / undo buttons that score without unlocking.
struct MatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchActivityAttributes.self) { context in
            LockScreenMatchView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(LiveStyle.ink)
                .activitySystemActionForegroundColor(LiveStyle.lime)
                .widgetURL(context.attributes.deepLink)
        } dynamicIsland: { context in
            let state = context.state
            let attributes = context.attributes
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandTeam(name: attributes.teamA, score: state.scoreA, side: .a, outcome: LiveOutcome(state: state))
                        .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandTeam(name: attributes.teamB, score: state.scoreB, side: .b, outcome: LiveOutcome(state: state))
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 3) {
                        HStack(spacing: 4) {
                            LiveDotMark(isFinished: state.isFinished, isStale: context.isStale)
                            Text(attributes.courtLabel)
                                .textCase(.uppercase)
                        }
                        .font(LiveStyle.label(.caption2, weight: .heavy))
                        .foregroundStyle(LiveStyle.lime)
                        Text(attributes.roundLabel)
                            .font(LiveStyle.label(.caption2, weight: .semibold))
                            .foregroundStyle(LiveStyle.muted)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 7) {
                        HStack(spacing: 10) {
                            StatusLine(state: state, isStale: context.isStale)
                            if let progress = state.progress, !state.isFinished {
                                LiveRail(progress: progress, height: 4)
                                    .frame(maxWidth: 120)
                            }
                        }
                        ScoreButtons(attributes: attributes, state: state, compact: true)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    LiveBall(size: 9)
                    Text(state.scoreA)
                        .font(LiveStyle.score(18))
                        .foregroundStyle(LiveStyle.lime)
                        .contentTransition(.numericText())
                }
                .padding(.leading, 2)
                .accessibilityLabel(Text(verbatim: "\(attributes.teamA) \(state.scoreA)"))
            } compactTrailing: {
                Text(state.scoreB)
                    .font(LiveStyle.score(18))
                    .foregroundStyle(LiveStyle.chalk)
                    .contentTransition(.numericText())
                    .padding(.trailing, 2)
                    .accessibilityLabel(Text(verbatim: "\(attributes.teamB) \(state.scoreB)"))
            } minimal: {
                ZStack {
                    if let progress = state.progress, !state.isFinished {
                        Circle()
                            .stroke(LiveStyle.chalk.opacity(0.18), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(LiveStyle.lime, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Text(verbatim: "\(state.scoreA)·\(state.scoreB)")
                        .font(LiveStyle.score(11))
                        .foregroundStyle(LiveStyle.lime)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(3)
                        .contentTransition(.numericText())
                }
                .accessibilityLabel(Text(verbatim: "\(attributes.teamA) \(state.scoreA), \(attributes.teamB) \(state.scoreB)"))
            }
            .widgetURL(attributes.deepLink)
            .keylineTint(LiveStyle.lime)
        }
    }
}

// MARK: - Lock Screen

struct LockScreenMatchView: View {
    let attributes: MatchActivityAttributes
    let state: MatchActivityAttributes.ContentState
    var isStale = false

    var body: some View {
        let outcome = LiveOutcome(state: state)
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                LiveDotMark(isFinished: state.isFinished, isStale: isStale)
                Text(verbatim: "\(attributes.courtLabel) · \(attributes.roundLabel)")
                    .textCase(.uppercase)
                    .foregroundStyle(LiveStyle.lime)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(attributes.tournamentName)
                    .foregroundStyle(LiveStyle.muted)
                    .lineLimit(1)
            }
            .font(LiveStyle.label(.caption, weight: .heavy))

            HStack(alignment: .center, spacing: 8) {
                LockTeam(name: attributes.teamA, score: state.scoreA, side: .a, outcome: outcome)
                CenterPiece(state: state, isStale: isStale)
                    .frame(maxWidth: .infinity)
                LockTeam(name: attributes.teamB, score: state.scoreB, side: .b, outcome: outcome)
            }

            ScoreButtons(attributes: attributes, state: state, compact: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            // Each team's half of the court glows faintly in its colour.
            HStack(spacing: 0) {
                LinearGradient(colors: [LiveStyle.lime.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, LiveStyle.chalk.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
            }
            .overlay {
                Rectangle()
                    .fill(LiveStyle.chalk.opacity(0.12))
                    .frame(width: 1)
            }
        }
        .foregroundStyle(LiveStyle.chalk)
    }
}

/// One team on the Lock Screen: name over a huge score, aligned to its edge.
private struct LockTeam: View {
    let name: String
    let score: String
    let side: LiveSide
    let outcome: LiveOutcome

    var body: some View {
        let isA = side == .a
        let won = outcome.winner == side
        VStack(alignment: isA ? .leading : .trailing, spacing: 0) {
            Text(name)
                .font(LiveStyle.label(.footnote, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(isA ? LiveStyle.lime : LiveStyle.chalk.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                if won && !isA { WinnerCrown() }
                Text(score)
                    .font(LiveStyle.score(56))
                    .foregroundStyle(isA ? LiveStyle.lime : LiveStyle.chalk)
                    .contentTransition(.numericText())
                    .invalidatableContent()
                if won && isA { WinnerCrown() }
            }
            .opacity(outcome.winner != nil && !won ? 0.5 : 1)
        }
        .frame(width: 104, alignment: isA ? .leading : .trailing)
        .accessibilityElement(children: .combine)
    }
}

/// Between the scores: the match situation over the progress rail.
private struct CenterPiece: View {
    let state: MatchActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(spacing: 6) {
            StatusLine(state: state, isStale: isStale)
            if let progress = state.progress, !state.isFinished {
                LiveRail(progress: progress, height: 4)
            }
        }
    }
}

/// Situation chip (Deuce, Golden point…) or the detail line, plus the stale notice.
private struct StatusLine: View {
    let state: MatchActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let parts = state.detail.components(separatedBy: " · ")
        Group {
            if isStale {
                Label("Score may be out of date", systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(LiveStyle.amber)
            } else if state.isFinished {
                Label { Text(state.detail) } icon: { Image(systemName: "flag.checkered") }
                    .foregroundStyle(LiveStyle.chalk.opacity(0.85))
            } else if !state.canScore {
                Text("Match won")
                    .textCase(.uppercase)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(LiveStyle.lime, in: Capsule())
                    .foregroundStyle(LiveStyle.ink)
            } else if parts.count > 1, let situation = parts.first, situation.rangeOfCharacter(from: .decimalDigits) == nil {
                // Games and sets: "Deuce · Games 3–2" → a chip and the games.
                HStack(spacing: 4) {
                    Text(situation)
                        .textCase(.uppercase)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(LiveStyle.chalk, in: Capsule())
                        .foregroundStyle(LiveStyle.ink)
                    Text(parts.dropFirst().joined(separator: " · "))
                        .foregroundStyle(LiveStyle.chalk.opacity(0.8))
                }
            } else {
                Text(state.detail)
                    .foregroundStyle(LiveStyle.chalk.opacity(0.8))
            }
        }
        .font(LiveStyle.label(.caption, weight: .heavy))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .contentTransition(.numericText())
        .transition(.push(from: .bottom))
        .id(state.detail + (isStale ? "-stale" : ""))
    }
}

private struct WinnerCrown: View {
    var body: some View {
        Image(systemName: "trophy.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(LiveStyle.gold)
            .accessibilityHidden(true)
    }
}

/// Lime dot while live, grey when finished, amber when stale.
private struct LiveDotMark: View {
    let isFinished: Bool
    let isStale: Bool

    var body: some View {
        Circle()
            .fill(isStale ? LiveStyle.amber : (isFinished ? LiveStyle.muted : LiveStyle.lime))
            .frame(width: 7, height: 7)
            .overlay {
                Circle().stroke((isFinished ? LiveStyle.muted : LiveStyle.lime).opacity(0.35), lineWidth: 3)
                    .padding(-2)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Dynamic Island team

private struct IslandTeam: View {
    let name: String
    let score: String
    let side: LiveSide
    let outcome: LiveOutcome

    var body: some View {
        let isA = side == .a
        VStack(alignment: isA ? .leading : .trailing, spacing: -1) {
            HStack(spacing: 3) {
                if outcome.winner == side && !isA { WinnerCrown() }
                Text(score)
                    .font(LiveStyle.score(46))
                    .foregroundStyle(isA ? LiveStyle.lime : LiveStyle.chalk)
                    .contentTransition(.numericText())
                    .invalidatableContent()
                if outcome.winner == side && isA { WinnerCrown() }
            }
            Text(name)
                .font(LiveStyle.label(.caption2, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(isA ? LiveStyle.lime : LiveStyle.chalk.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: isA ? .leading : .trailing)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Buttons

/// +1 Team A, Undo, +1 Team B. Hidden once the match is decided or finished.
struct ScoreButtons: View {
    let attributes: MatchActivityAttributes
    let state: MatchActivityAttributes.ContentState
    var compact = false

    var body: some View {
        if state.canScore {
            HStack(spacing: 8) {
                Button(intent: RecordPointIntent(tournamentID: attributes.tournamentID, matchID: attributes.matchID, side: "a")) {
                    Text("+1 A")
                        .frame(maxWidth: .infinity, minHeight: height)
                        .foregroundStyle(LiveStyle.ink)
                        .background(LiveStyle.lime, in: Capsule())
                }
                .accessibilityLabel("Point for \(attributes.teamA)")
                Button(intent: UndoPointIntent(tournamentID: attributes.tournamentID, matchID: attributes.matchID)) {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: height + 10, height: height)
                        .foregroundStyle(LiveStyle.chalk)
                        .background(LiveStyle.raised, in: Capsule())
                }
                .accessibilityLabel("Undo last point")
                Button(intent: RecordPointIntent(tournamentID: attributes.tournamentID, matchID: attributes.matchID, side: "b")) {
                    Text("+1 B")
                        .frame(maxWidth: .infinity, minHeight: height)
                        .foregroundStyle(LiveStyle.ink)
                        .background(LiveStyle.chalk, in: Capsule())
                }
                .accessibilityLabel("Point for \(attributes.teamB)")
            }
            .buttonStyle(.plain)
            .font(LiveStyle.label(.subheadline, weight: .heavy))
        } else if !state.isFinished {
            Text("Open PadelOS to confirm the result")
                .font(LiveStyle.label(.caption, weight: .bold))
                .foregroundStyle(LiveStyle.muted)
                .frame(maxWidth: .infinity, minHeight: height)
        } else {
            EmptyView()
        }
    }

    private var height: CGFloat { compact ? 32 : 34 }
}

// MARK: - Outcome

enum LiveSide { case a, b }

/// Who won, read from the big figures once the match is finished (points, or sets won).
struct LiveOutcome {
    let winner: LiveSide?

    init(state: MatchActivityAttributes.ContentState) {
        guard state.isFinished || !state.canScore, let a = Int(state.scoreA), let b = Int(state.scoreB), a != b else {
            winner = nil
            return
        }
        winner = a > b ? .a : .b
    }
}
