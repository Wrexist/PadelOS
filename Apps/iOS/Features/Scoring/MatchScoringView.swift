import SwiftUI
import UIKit
import PadelCore
import PadelStore

/// Scoring for one match: the split court fills the screen, the situation and progress
/// sit above it, and Undo, Set Score and Finish are always on the glass bar below.
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
    @State private var celebration = 0

    var body: some View {
        Group {
            if let tournament = store.tournament(tournamentID), let match = tournament.match(matchID) {
                content(tournament, match)
            } else {
                EmptyStateView(symbol: "questionmark.circle", title: "Match not found", message: "The schedule may have changed.")
            }
        }
        .screenBackground()
        .onAppear {
            setIdleTimer(disabled: settings.settings.keepScreenAwakeWhileScoring)
            model.liveActivities.start(tournamentID: tournamentID, matchID: matchID)
        }
        .onDisappear { setIdleTimer(disabled: false) }
    }

    private func setIdleTimer(disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }

    @ViewBuilder
    private func content(_ tournament: Tournament, _ match: Match) -> some View {
        let rule = tournament.scoringRule(for: match)
        let editable = tournament.status == .active && !match.isLogCompacted
        let awaiting = ScoringEngine.isAwaitingConfirmation(match, rule: rule)
        let canUndo = editable && !match.isCompleted && ScoringEngine.lastUndoableEvent(in: match) != nil
        VStack(spacing: Theme.Spacing.m) {
            if let message = model.errorMessage {
                MessageBanner(style: .error, message: message, onDismiss: { model.errorMessage = nil })
            }
            statusStrip(match, rule: rule)
            ScoringCourt(
                a: side(.a, tournament: tournament, match: match, rule: rule),
                b: side(.b, tournament: tournament, match: match, rule: rule),
                situation: situation(match, rule: rule),
                canScore: editable && !match.isCompleted && !awaiting,
                canUndo: canUndo,
                winner: match.isCompleted ? ScoringEngine.winner(of: match) : nil,
                isFinished: match.isCompleted,
                hapticsEnabled: settings.settings.hapticsEnabled,
                onPoint: { side in
                    model.run { try store.recordPoint(side, match: match.id, in: tournamentID) }
                },
                onUndo: {
                    model.run { try store.undo(match: match.id, in: tournamentID) }
                },
                onEnterResult: {
                    if editable { showResultEntry = true }
                }
            )
            .frame(minHeight: 260)
            if !match.hasStarted && editable {
                Text("Tap a side to score. Hold it to enter a result, pull the court down to undo.")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if match.isCompleted {
                completedPanel(match, editable: editable)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if editable {
                actionBar(tournament, match, rule: rule, awaiting: awaiting, canUndo: canUndo)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.s)
        .padding(.top, Theme.Spacing.xs)
        .animation(Motion.smooth, value: match.isCompleted)
        .animation(Motion.smooth, value: awaiting)
        .animation(Motion.smooth, value: match.hasStarted)
        .overlay { ConfettiBurst(trigger: celebration).ignoresSafeArea() }
        .navigationTitle(Text("Court \(match.court)"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Court \(match.court)")
                        .font(.headline.width(.expanded))
                    Text(verbatim: roundLabel(tournament, match))
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .sensoryFeedback(.success, trigger: match.isCompleted) { _, new in
            settings.settings.hapticsEnabled && new
        }
        .sensoryFeedback(.warning, trigger: awaiting) { _, new in
            settings.settings.hapticsEnabled && new
        }
        .onChange(of: match.isCompleted) { old, new in
            if new && !old { celebration += 1 }
        }
        .confirmationDialog("Finish match \(match.resultText(rule: rule))?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish Match") {
                model.run { try store.finish(match: match.id, in: tournamentID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(rule.isSets
                ? "\(tournament.sideName(match.sideA)) v \(tournament.sideName(match.sideB)): \(match.resultText(rule: rule)). The result counts towards the standings."
                : "\(tournament.sideName(match.sideA)) \(match.score.a), \(tournament.sideName(match.sideB)) \(match.score.b). The result counts towards the standings.")
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
        guard let round = tournament.rounds.first(where: { $0.number == match.roundNumber }) else { return "" }
        return tournament.roundTitle(round, includeTotal: true)
    }

    // MARK: Court content

    private func side(_ side: TeamSide, tournament: Tournament, match: Match, rule: ScoringRule) -> ScoringCourt.Side {
        let names = tournament.sideNames(of: match, side)
        guard let rules = rule.setsRules else {
            let value = match.score[side]
            return ScoringCourt.Side(names: names, score: value.formatted(), numeric: Double(value), detail: nil)
        }
        let state = match.sets ?? SetsState()
        if state.isDecided {
            let sets = state.setsWon[side]
            return ScoringCourt.Side(names: names, score: sets.formatted(), numeric: Double(sets), detail: String(localized: "Sets"))
        }
        let label = state.pointLabel(side, rules: rules)
        return ScoringCourt.Side(
            names: names,
            score: label,
            numeric: Double(label),
            detail: "\(String(localized: "Games")) \(state.games[side].formatted())"
        )
    }

    private func situation(_ match: Match, rule: ScoringRule) -> String? {
        guard let rules = rule.setsRules, let state = match.sets, !match.isCompleted else { return nil }
        return state.situation(rules: rules)
    }

    // MARK: Status

    /// Caption, sets summary and progress. The caption carries the spoken score
    /// ("Score 12 to 8") so VoiceOver users can check it at any time.
    @ViewBuilder
    private func statusStrip(_ match: Match, rule: ScoringRule) -> some View {
        if let rules = rule.setsRules {
            let state = match.sets ?? SetsState()
            let decided = state.isDecided
            let pointsA = state.pointLabel(.a, rules: rules)
            let pointsB = state.pointLabel(.b, rules: rules)
            VStack(spacing: 6) {
                Text(verbatim: state.summary().isEmpty ? "0-0" : state.summary())
                    .font(.padelScoreboard(size: 26))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Motion.snappy, value: state)
                    .accessibilityIdentifier("setsSummary")
                Text(verbatim: decided
                    ? (match.isCompleted ? L10n.format("Final score %@", state.summary()) : L10n.format("Match won · %@", state.summary()))
                    : (state.situation(rules: rules) ?? L10n.format("Games %lld–%lld", state.games.a, state.games.b) + " · " + rules.localizedName))
                    .font(.padelMeta.weight(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(decided
                        ? String(localized: "Sets \(state.setsWon.a) to \(state.setsWon.b), \(state.summary())")
                        : String(localized: "Points \(pointsA) to \(pointsB). Games \(state.games.a) to \(state.games.b)."))
                    .accessibilityIdentifier("scoreLabel")
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: Theme.Spacing.s) {
                // Uppercased in the string, not with .textCase: that would also uppercase
                // the spoken score label below.
                Text(verbatim: (match.isCompleted ? String(localized: "Final score") : rule.scoreCaption).localizedUppercase)
                    .font(.padelEyebrow)
                    .tracking(1)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityLabel("Score \(match.score.a) to \(match.score.b)")
                    .accessibilityIdentifier("scoreLabel")
                if let progress = match.progress(rule: rule), !match.isCompleted {
                    ProgressBar(value: progress, height: 5)
                        .frame(maxWidth: 240)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Actions

    private func actionBar(_ tournament: Tournament, _ match: Match, rule: ScoringRule, awaiting: Bool, canUndo: Bool) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            if awaiting {
                Label(rule.isSets ? "Match won. Confirm the result." : "\(rule.totalPoints ?? 0) points reached. Confirm the result.", systemImage: "flag.checkered")
                    .font(.padelMeta.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            HStack(spacing: Theme.Spacing.s) {
                ScoringActionButton(title: "Undo", symbol: "arrow.uturn.backward", identifier: "undoButton", isEnabled: canUndo) {
                    model.run { try store.undo(match: match.id, in: tournamentID) }
                }
                ScoringActionButton(title: "Set Score", symbol: "square.grid.3x3.fill", identifier: "setScoreButton", isEnabled: true) {
                    showResultEntry = true
                }
                ScoringActionButton(title: "Finish", symbol: "checkmark", identifier: "finishMatchButton", isEnabled: ScoringEngine.canFinish(match, rule: rule), isHighlighted: awaiting) {
                    confirmFinish = true
                }
            }
            .padding(6)
            .glassSurface(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private func completedPanel(_ match: Match, editable: Bool) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "checkmark.seal.fill")
                    .symbolEffect(.bounce, value: celebration)
                    .accessibilityHidden(true)
                Text("Match finished")
            }
            .font(.padelHeadline)
            .foregroundStyle(Theme.Colors.accentText)
            Group {
                if let winner = ScoringEngine.winner(of: match) {
                    Text(winner == .a ? "Team A won" : "Team B won")
                } else {
                    Text("Draw")
                }
            }
            .font(.padelMeta.weight(.semibold))
            .foregroundStyle(Theme.Colors.textSecondary)
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
    }
}

/// One of the three buttons on the scoring bar: a big symbol over a short label.
struct ScoringActionButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let identifier: String
    var isEnabled: Bool
    var isHighlighted = false
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.title3.weight(.bold))
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isHighlighted ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isHighlighted ? Theme.Colors.accent : Theme.Colors.surfaceRaised.opacity(0.6))
                    .shadow(color: Theme.Colors.accent.opacity(isHighlighted ? (glowing ? 0.85 : 0.2) : 0), radius: 14)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onChange(of: isHighlighted, initial: true) { _, highlighted in
            glowing = false
            guard highlighted, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { glowing = true }
        }
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(identifier)
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
                if let rules = tournament.scoringRule(for: match).setsRules {
                    SetsResultForm(tournament: tournament, match: match, rules: rules)
                } else {
                    form(tournament, match)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func form(_ tournament: Tournament, _ match: Match) -> some View {
        let rule = tournament.scoringRule(for: match)
        let total = rule.totalPoints
        Form {
            if let error {
                Text(verbatim: error).foregroundStyle(Theme.Colors.danger).font(.padelMeta)
            }
            Section {
                ResultScoreboard(
                    nameA: tournament.sideName(match.sideA), scoreA: scoreA,
                    nameB: tournament.sideName(match.sideB), scoreB: scoreB
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
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

/// Enter a games/sets result set by set (e.g. 6-4, 3-6, 10-8). The Save button is only
/// enabled when the sets form a legal, complete match under the tournament's rules.
struct SetsResultForm: View {
    @Environment(TournamentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tournament: Tournament
    let match: Match
    let rules: SetsRules
    @State private var sets: [Score] = []
    @State private var error: String?
    @State private var loaded = false

    private var isValid: Bool {
        ScoringEngine.validateSets(sets, rule: tournament.scoringRule(for: match)) == nil
    }

    var body: some View {
        Form {
            if let error {
                Text(verbatim: error).foregroundStyle(Theme.Colors.danger).font(.padelMeta)
            }
            ForEach(sets.indices, id: \.self) { index in
                Section(title(for: index)) {
                    Stepper(value: binding(index, .a), in: 0...maximum(for: index)) {
                        row(tournament.sideName(match.sideA), sets[index].a)
                    }
                    .accessibilityIdentifier("set\(index + 1)A")
                    Stepper(value: binding(index, .b), in: 0...maximum(for: index)) {
                        row(tournament.sideName(match.sideB), sets[index].b)
                    }
                    .accessibilityIdentifier("set\(index + 1)B")
                }
                .listRowBackground(Theme.Colors.surface)
            }
            Section {
                if sets.count < rules.setsToWin * 2 - 1 {
                    Button("Add Set") { sets.append(Score(a: rules.gamesPerSet, b: 0)) }
                }
                if sets.count > 1 {
                    Button("Remove Last Set", role: .destructive) { sets.removeLast() }
                }
            } footer: {
                if isValid {
                    Text("Result: \(summary)")
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enter every set until one team has won \(rules.setsToWin) sets.")
                        Text(verbatim: rules.localizedName)
                    }
                }
            }
            .listRowBackground(Theme.Colors.surface)
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(match.isCompleted ? "Correct Result" : "Enter Result")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                    .accessibilityIdentifier("saveResultButton")
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let existing = match.sets, existing.isDecided {
                sets = existing.completedSets
            } else if let existing = match.sets, !existing.completedSets.isEmpty {
                sets = existing.completedSets + [existing.games]
            } else {
                sets = [Score(a: rules.gamesPerSet, b: max(0, rules.gamesPerSet - 2))]
            }
        }
    }

    private var summary: String {
        SetsState.fromFinalSets(sets, rules: rules)?.summary() ?? ""
    }

    /// The deciding set may be a match tie-break, scored in points.
    private func isSuperTieBreak(_ index: Int) -> Bool {
        rules.superTieBreakDecider && rules.setsToWin > 1 && index == rules.setsToWin * 2 - 2
    }

    private func title(for index: Int) -> String {
        isSuperTieBreak(index) ? String(localized: "Match tie-break") : String(localized: "Set \(index + 1)")
    }

    private func maximum(for index: Int) -> Int {
        isSuperTieBreak(index) ? 40 : rules.gamesPerSet + (rules.tieBreak ? 1 : 10)
    }

    private func binding(_ index: Int, _ side: TeamSide) -> Binding<Int> {
        Binding(get: { sets.indices.contains(index) ? sets[index][side] : 0 },
                set: { value in if sets.indices.contains(index) { sets[index][side] = value } })
    }

    private func row(_ name: String, _ value: Int) -> some View {
        HStack {
            Text(name).font(.padelName).lineLimit(1)
            Spacer()
            Text("\(value)").font(.padelScore(size: 24))
        }
        .accessibilityElement(children: .combine)
    }

    private func save() {
        do {
            try store.enterSetsResult(sets, match: match.id, in: tournament.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The result being entered, scoreboard style, rolling as the steppers change.
struct ResultScoreboard: View {
    let nameA: String
    let scoreA: Int
    let nameB: String
    let scoreB: Int

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            column(nameA, scoreA, tint: Theme.Colors.accentText)
            Text(verbatim: "–")
                .font(.padelScoreboard(size: 48))
                .foregroundStyle(Theme.Colors.textSecondary)
            column(nameB, scoreB, tint: Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.s)
        .animation(Motion.snappy, value: scoreA)
        .animation(Motion.snappy, value: scoreB)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Score \(scoreA) to \(scoreB)"))
    }

    private func column(_ name: String, _ score: Int, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(score)")
                .font(.padelScoreboard(size: 64))
                .foregroundStyle(tint)
                .contentTransition(.numericText(value: Double(score)))
            Text(verbatim: name)
                .font(.padelMeta.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}
