import SwiftUI
import PadelCore
import PadelStore

/// The core watch screen: two huge tap targets, one per team. One deliberate tap = one
/// point. Undo is always one tap away; finishing needs a confirmation.
struct WatchScoringView: View {
    @Environment(WatchModel.self) private var model
    @Environment(WatchStore.self) private var store
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let tournamentID: TournamentID
    let matchID: MatchID
    @Binding var path: [WatchRoute]
    @State private var confirmFinish = false
    @State private var showActions = false

    var body: some View {
        Group {
            if let tournament = store.state.tournament(tournamentID), let match = tournament.match(matchID) {
                if match.isCompleted {
                    WatchFinishedView(tournament: tournament, match: match, path: $path)
                } else {
                    scoring(tournament, match)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "questionmark.circle").font(.title3)
                    Text("This match is no longer in the schedule.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .navigationBarBackButtonHidden(false)
    }

    private func scoring(_ tournament: Tournament, _ match: Match) -> some View {
        let rule = tournament.configuration.scoring
        let awaiting = ScoringEngine.isAwaitingConfirmation(match, rule: rule)
        return VStack(spacing: 4) {
            header(tournament, match)
            HStack(spacing: 6) {
                teamButton(.a, tournament: tournament, match: match, enabled: !awaiting)
                teamButton(.b, tournament: tournament, match: match, enabled: !awaiting)
            }
            footer(tournament, match, rule: rule, awaiting: awaiting)
        }
        .padding(.horizontal, 2)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Finish \(match.resultText(rule: rule))?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish Match") {
                if store.finish(match: match.id, tournament: tournamentID) {
                    WatchHaptics.success()
                } else {
                    WatchHaptics.failure()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showActions) {
            WatchActionsView(tournament: tournament, match: match, path: $path, confirmFinish: $confirmFinish)
        }
    }

    private func header(_ tournament: Tournament, _ match: Match) -> some View {
        HStack(spacing: 4) {
            Button {
                path.removeLast()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Text(tournament.shortProgressLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
            Text("Court \(match.court)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.Colors.onAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Theme.Colors.accent, in: Capsule())
            Spacer(minLength: 0)
            syncGlyph
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var syncGlyph: some View {
        switch store.syncStatus {
        case .pending(let count, _):
            Label("\(count)", systemImage: "arrow.up.circle")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.warning)
                .accessibilityLabel("\(count) changes waiting to sync")
        case .upToDate:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityLabel("Synced")
        case .waitingForPhone:
            EmptyView()
        }
    }

    private func teamButton(_ side: TeamSide, tournament: Tournament, match: Match, enabled: Bool) -> some View {
        let isA = side == .a
        let names = tournament.sideNames(of: match, side)
        let fill = isA ? Theme.Colors.accent : Theme.Colors.surfaceRaised
        let text = isA ? Theme.Colors.onAccent : Theme.Colors.textPrimary
        let rules = tournament.configuration.scoring.setsRules
        // Games/sets: the big figure is the current game point (15, 30, 40, Ad), with
        // games and sets underneath. Rally points: the big figure is the score.
        let bigText = rules.map { match.sets?.pointLabel(side, rules: $0) ?? "0" } ?? "\(match.score[side])"
        let detail: String? = rules.map { _ in
            let state = match.sets ?? SetsState()
            return state.completedSets.isEmpty ? "Games \(state.games[side])" : "G \(state.games[side]) · S \(state.setsWon[side])"
        }
        return Button {
            if store.recordPoint(side, match: match.id, tournament: tournamentID) {
                WatchHaptics.point()
            } else {
                WatchHaptics.failure()
            }
        } label: {
            VStack(spacing: 0) {
                ForEach(names, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Text(bigText)
                    .font(.padelScore(size: 46))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                if let detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .opacity(0.8)
                }
                Spacer(minLength: 0)
                Text(isA ? "+1 Team A" : "+1 Team B")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.8)
            }
            .foregroundStyle(text)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fill.opacity(isLuminanceReduced ? 0.35 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .animation(.snappy(duration: 0.15), value: match.score)
        .accessibilityLabel("Point for \(names.joined(separator: " and ")). \(rules == nil ? "Score" : "Points") \(bigText).")
        .accessibilityIdentifier(isA ? "watchPointA" : "watchPointB")
    }

    private func footer(_ tournament: Tournament, _ match: Match, rule: ScoringRule, awaiting: Bool) -> some View {
        HStack(spacing: 6) {
            Button {
                if store.undo(match: match.id, tournament: tournamentID) {
                    WatchHaptics.undo()
                } else {
                    WatchHaptics.failure()
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 34)
                    .background(Theme.Colors.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(ScoringEngine.lastUndoableEvent(in: match) == nil)
            .accessibilityLabel("Undo last point")

            if awaiting {
                Button {
                    confirmFinish = true
                } label: {
                    Text(rule.isSets ? "Finish match" : "Finish \(match.score.a)–\(match.score.b)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Colors.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Theme.Colors.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watchFinish")
            } else {
                Text(progressText(match, rule: rule))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
            }

            Button {
                showActions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 34)
                    .background(Theme.Colors.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Match actions")
        }
    }

    private func progressText(_ match: Match, rule: ScoringRule) -> String {
        if let rules = rule.setsRules {
            let state = match.sets ?? SetsState()
            return state.situation(rules: rules) ?? (state.summary().isEmpty ? "0-0" : state.summary())
        }
        if let total = rule.totalPoints { return "\(match.score.total)/\(total)" }
        return "Timed"
    }
}

/// Secondary actions, kept off the main screen to prevent accidental taps.
struct WatchActionsView: View {
    @Environment(WatchModel.self) private var model
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tournament: Tournament
    let match: Match
    @Binding var path: [WatchRoute]
    @Binding var confirmFinish: Bool

    var body: some View {
        List {
            Button {
                if store.undo(match: match.id, tournament: tournament.id) { WatchHaptics.undo() }
                dismiss()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(ScoringEngine.lastUndoableEvent(in: match) == nil)

            Button {
                dismiss()
                confirmFinish = true
            } label: {
                Label("Finish Match", systemImage: "flag.checkered")
            }
            .disabled(!ScoringEngine.canFinish(match, rule: tournament.configuration.scoring))
            .foregroundStyle(Theme.Colors.accent)

            Button {
                dismiss()
                path = [.courts(tournament.id)]
            } label: {
                Label("Switch Court", systemImage: "square.grid.2x2")
            }

            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tournament.sideNames(of: match, .a).joined(separator: " & ")).font(.caption2)
                    Text("vs").font(.caption2).foregroundStyle(Theme.Colors.textSecondary)
                    Text(tournament.sideNames(of: match, .b).joined(separator: " & ")).font(.caption2)
                }
            }
        }
        .navigationTitle("Match")
    }
}

struct WatchFinishedView: View {
    @Environment(WatchModel.self) private var model
    @Environment(WatchStore.self) private var store
    let tournament: Tournament
    let match: Match
    @Binding var path: [WatchRoute]

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityHidden(true)
                Text("Match Finished")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.accent)
                Text(tournament.configuration.scoring.isSets ? match.resultText(rule: tournament.configuration.scoring) : "\(match.score.a) – \(match.score.b)")
                    .font(.padelScore(size: tournament.configuration.scoring.isSets ? 24 : 36))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accessibilityLabel("Final score \(match.resultText(rule: tournament.configuration.scoring))")
                Text(winnerText)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                if let next = model.activeMatch(in: tournament), next.id != match.id {
                    Button {
                        model.selectedMatchID = next.id
                        path = [.scoring(tournament.id, next.id)]
                    } label: {
                        Text("Next: Court \(next.court)\(next.roundNumber != match.roundNumber ? " · R\(next.roundNumber)" : "")")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Colors.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Theme.Colors.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button("Done") { path.removeAll() }
                    .accessibilityIdentifier("watchDone")
                if !match.isLogCompacted && tournament.status == .active {
                    Button("Reopen Match") {
                        _ = store.reopen(match: match.id, tournament: tournament.id)
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    private var winnerText: String {
        guard let winner = ScoringEngine.winner(of: match) else { return "Draw" }
        return tournament.sideNames(of: match, winner).joined(separator: " & ") + " win"
    }
}
