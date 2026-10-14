import SwiftUI
import UIKit
import PadelCore
import PadelStore

/// Large, one-tap scoring for a single match.
struct MatchScoringView: View {
    @Environment(AppModel.self) private var model
    @Environment(TournamentStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let tournamentID: TournamentID
    let matchID: MatchID
    @State private var confirmFinish = false
    @State private var showResultEntry = false
    @State private var confirmReopen = false
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 88
    @ScaledMetric(relativeTo: .title) private var buttonSize: CGFloat = 104

    var body: some View {
        Group {
            if let tournament = store.tournament(tournamentID), let match = tournament.match(matchID) {
                content(tournament, match)
            } else {
                EmptyStateView(symbol: "questionmark.circle", title: "Match not found", message: "The schedule may have changed.")
            }
        }
        .screenBackground()
        .onAppear { setIdleTimer(disabled: settings.settings.keepScreenAwakeWhileScoring) }
        .onDisappear { setIdleTimer(disabled: false) }
    }

    private func setIdleTimer(disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }

    @ViewBuilder
    private func content(_ tournament: Tournament, _ match: Match) -> some View {
        let rule = tournament.configuration.scoring
        let editable = tournament.status == .active && !match.isLogCompacted
        let awaiting = ScoringEngine.isAwaitingConfirmation(match, rule: rule)
        VStack(spacing: Theme.Spacing.l) {
            if let message = model.errorMessage {
                MessageBanner(style: .error, message: message, onDismiss: { model.errorMessage = nil })
            }
            names(tournament, match)
            scoreDisplay(match, rule: rule)
            if match.isCompleted {
                completedPanel(match, editable: editable)
            } else if editable {
                scoringButtons(match, rule: rule, awaiting: awaiting)
            }
            Spacer(minLength: 0)
            if !match.isCompleted && editable {
                actionBar(tournament, match, rule: rule, awaiting: awaiting)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.l)
        .navigationTitle("Court \(match.court)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Court \(match.court)").font(.headline)
                    Text(roundLabel(tournament, match)).font(.caption2).foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .sensoryFeedback(.increase, trigger: match.score.total) { old, new in
            settings.settings.hapticsEnabled && new > old
        }
        .sensoryFeedback(.success, trigger: match.isCompleted) { _, new in
            settings.settings.hapticsEnabled && new
        }
        .confirmationDialog("Finish match \(match.score.a)–\(match.score.b)?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish Match") {
                model.run { try store.finish(match: match.id, in: tournamentID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(tournament.sideName(match.sideA)) \(match.score.a), \(tournament.sideName(match.sideB)) \(match.score.b). The result counts towards the standings.")
        }
        .confirmationDialog("Reopen this match?", isPresented: $confirmReopen, titleVisibility: .visible) {
            Button("Reopen Match") {
                model.run { try store.reopen(match: match.id, in: tournamentID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The result is removed from the standings until the match is finished again.")
        }
        .sheet(isPresented: $showResultEntry) {
            ResultEntrySheet(tournamentID: tournamentID, matchID: matchID)
        }
    }

    private func roundLabel(_ tournament: Tournament, _ match: Match) -> String {
        let round = tournament.rounds.first { $0.number == match.roundNumber }
        return round?.kind == .final ? "Final round" : "Round \(match.roundNumber) of \(tournament.configuration.roundCount)"
    }

    private func names(_ tournament: Tournament, _ match: Match) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(tournament.sideNames(of: match, .a), id: \.self) { Text($0) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(tournament.sideNames(of: match, .b), id: \.self) { Text($0) }
            }
        }
        .font(.title2.weight(.semibold))
        .foregroundStyle(Theme.Colors.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.top, Theme.Spacing.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tournament.sideNames(of: match, .a).joined(separator: " and ")) versus \(tournament.sideNames(of: match, .b).joined(separator: " and "))")
    }

    private func scoreDisplay(_ match: Match, rule: ScoringRule) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Text("\(match.score.a)")
                    .foregroundStyle(Theme.Colors.accentText)
                    .contentTransition(.numericText(value: Double(match.score.a)))
                Text("–")
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("\(match.score.b)")
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.numericText(value: Double(match.score.b)))
            }
            .font(.padelScore(size: scoreSize))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .animation(.snappy(duration: 0.2), value: match.score)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Score \(match.score.a) to \(match.score.b)")
            .accessibilityIdentifier("scoreLabel")

            Text(match.isCompleted ? "Final score" : rule.scoreCaption)
                .font(.padelMeta)
                .foregroundStyle(Theme.Colors.textSecondary)
            if let progress = match.progress(rule: rule), !match.isCompleted {
                ProgressBar(value: progress).frame(maxWidth: 220)
            }
        }
    }

    private func scoringButtons(_ match: Match, rule: ScoringRule, awaiting: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xl) {
            pointButton(.a, match: match, enabled: !awaiting)
            pointButton(.b, match: match, enabled: !awaiting)
        }
        .padding(.top, Theme.Spacing.m)
    }

    private func pointButton(_ side: TeamSide, match: Match, enabled: Bool) -> some View {
        let isA = side == .a
        return VStack(spacing: Theme.Spacing.s) {
            Button {
                model.run { try store.recordPoint(side, match: match.id, in: tournamentID) }
            } label: {
                Text("+1")
                    .font(.system(size: buttonSize * 0.3, weight: .bold, design: .rounded))
                    .foregroundStyle(isA ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(isA ? Theme.Colors.accent : Theme.Colors.surfaceRaised, in: Circle())
                    .overlay(Circle().strokeBorder(isA ? .clear : Theme.Colors.separator, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.35)
            .accessibilityLabel("Point for Team \(isA ? "A" : "B")")
            .accessibilityIdentifier(isA ? "pointTeamA" : "pointTeamB")
            Text(isA ? "Team A" : "Team B")
                .font(.padelMeta.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private func actionBar(_ tournament: Tournament, _ match: Match, rule: ScoringRule, awaiting: Bool) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            if awaiting {
                Text("\(rule.totalPoints ?? 0) points reached. Confirm the result.")
                    .font(.padelMeta.weight(.medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            HStack(spacing: Theme.Spacing.l) {
                circleAction("Undo", symbol: "arrow.uturn.backward", identifier: "undoButton", enabled: ScoringEngine.lastUndoableEvent(in: match) != nil) {
                    model.run { try store.undo(match: match.id, in: tournamentID) }
                }
                circleAction("Set Score", symbol: "square.grid.3x3", identifier: "setScoreButton", enabled: true) {
                    showResultEntry = true
                }
                circleAction("Finish", symbol: "checkmark", identifier: "finishMatchButton", enabled: ScoringEngine.canFinish(match, rule: rule), highlighted: awaiting) {
                    confirmFinish = true
                }
            }
        }
    }

    private func circleAction(_ title: String, symbol: String, identifier: String, enabled: Bool, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(highlighted ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                    .frame(width: 56, height: 56)
                    .background(highlighted ? Theme.Colors.accent : Theme.Colors.surface, in: Circle())
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private func completedPanel(_ match: Match, editable: Bool) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Label("Match finished", systemImage: "checkmark.seal.fill")
                .font(.padelSection)
                .foregroundStyle(Theme.Colors.accentText)
            if let winner = match.score.winner {
                Text("Team \(winner == .a ? "A" : "B") won")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                Text("Draw")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if editable {
                HStack(spacing: Theme.Spacing.m) {
                    Button("Correct Result") { showResultEntry = true }
                        .buttonStyle(.padelSecondary)
                        .accessibilityIdentifier("correctResultButton")
                    Button("Reopen") { confirmReopen = true }
                        .buttonStyle(.padelSecondary)
                }
                Button("Back to Tournament") { dismiss() }
                    .buttonStyle(.padelPrimary)
                    .accessibilityIdentifier("backToTournamentButton")
            }
        }
        .padding(.top, Theme.Spacing.l)
    }
}

/// Enter or correct a score directly. For fixed-total matches the second score follows
/// from the first, so a final result is two taps.
struct ResultEntrySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(TournamentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tournamentID: TournamentID
    let matchID: MatchID
    @State private var scoreA = 0
    @State private var scoreB = 0
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            if let tournament = store.tournament(tournamentID), let match = tournament.match(matchID) {
                form(tournament, match)
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func form(_ tournament: Tournament, _ match: Match) -> some View {
        let rule = tournament.configuration.scoring
        let total = rule.totalPoints
        Form {
            if let error {
                Text(error).foregroundStyle(Theme.Colors.danger).font(.padelMeta)
            }
            Section {
                Stepper(value: Binding(get: { scoreA }, set: { value in
                    scoreA = value
                    if let total { scoreB = max(0, total - value) }
                }), in: 0...(total ?? ScoringRule.maximumTimedPoints)) {
                    scoreRow(tournament.sideName(match.sideA), scoreA)
                }
                .accessibilityIdentifier("scoreAStepper")
                Stepper(value: Binding(get: { scoreB }, set: { value in
                    scoreB = value
                    if let total { scoreA = max(0, total - value) }
                }), in: 0...(total ?? ScoringRule.maximumTimedPoints)) {
                    scoreRow(tournament.sideName(match.sideB), scoreB)
                }
                .accessibilityIdentifier("scoreBStepper")
            } footer: {
                if let total {
                    Text("Scores always add up to \(total).")
                }
            }
            .listRowBackground(Theme.Colors.surface)
            if match.isCompleted {
                Section {
                    Text("Correcting a finished match updates the standings. Rounds that have already started are never changed.")
                        .font(.padelMeta)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .listRowBackground(Theme.Colors.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(match.isCompleted ? "Correct Result" : "Enter Result")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(match) }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("saveResultButton")
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if match.hasStarted {
                scoreA = match.score.a
                scoreB = match.score.b
            } else if let total {
                scoreA = total / 2
                scoreB = total - total / 2
            }
            if let total, scoreA + scoreB != total { scoreB = max(0, total - scoreA) }
        }
    }

    private func scoreRow(_ name: String, _ value: Int) -> some View {
        HStack {
            Text(name).font(.padelName).lineLimit(1)
            Spacer()
            Text("\(value)").font(.padelScore(size: 28))
        }
        .accessibilityElement(children: .combine)
    }

    private func save(_ match: Match) {
        do {
            try store.enterResult(Score(a: scoreA, b: scoreB), match: match.id, in: tournamentID)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
