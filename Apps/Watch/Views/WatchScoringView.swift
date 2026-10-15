import SwiftUI
import PadelCore
import PadelStore

/// The core watch screen: the display is the court, split by the net. Tap a half to give
/// that team the point; the ball flies over to their side. Undo is one tap away (or a
/// deliberate turn of the Digital Crown); finishing needs a confirmation.
struct WatchScoringView: View {
    @Environment(WatchModel.self) private var model
    @Environment(WatchStore.self) private var store
    @Environment(\.isLuminanceReduced) private var systemLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tournamentID: TournamentID
    let matchID: MatchID
    @Binding var path: [WatchRoute]

    @State private var confirmFinish = false
    @State private var showActions = false
    /// Where the ball rests: the side that won the last point (nil before the first one).
    @State private var ballSide: TeamSide?
    /// Increments on every point or undo; drives the ball's arc.
    @State private var flights = 0
    /// Increments per side on each of its points; drives the half's flash and digit bump.
    @State private var hitsA = 0
    @State private var hitsB = 0
    /// Digital Crown travel towards an undo (−1...1, undo at either end).
    @State private var crown = 0.0
    @State private var crownIdle: Task<Void, Never>?
    @State private var undoToast = 0
    @FocusState private var crownFocused: Bool

    private var isDimmed: Bool { systemLuminanceReduced || WatchDemo.forcesLuminanceReduced }

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

    // MARK: Layout

    private func scoring(_ tournament: Tournament, _ match: Match) -> some View {
        let rule = tournament.scoringRule(for: match)
        let awaiting = ScoringEngine.isAwaitingConfirmation(match, rule: rule)
        let callout = WatchScoreCallout(match: match, rule: rule, awaiting: awaiting)
        return ZStack {
            WatchCourtSurface(dimmed: isDimmed, winner: awaiting ? ScoringEngine.winner(of: match) : nil)

            VStack(spacing: 2) {
                header(tournament, match)
                GeometryReader { proxy in
                    ZStack {
                        HStack(spacing: 0) {
                            half(.a, tournament: tournament, match: match, rule: rule, enabled: !awaiting, size: proxy.size)
                            half(.b, tournament: tournament, match: match, rule: rule, enabled: !awaiting, size: proxy.size)
                        }
                        if !isDimmed {
                            ball(in: proxy.size)
                            CalloutSweep(callout: callout, reduceMotion: reduceMotion)
                        }
                    }
                }
                footer(tournament, match, rule: rule, awaiting: awaiting, callout: callout)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .ignoresSafeArea(.container, edges: .top)

            UndoToast(trigger: undoToast)
        }
        .toolbar(.hidden, for: .navigationBar)
        .focusable()
        .focusEffectDisabled()
        .focused($crownFocused)
        .digitalCrownRotation($crown, from: -1, through: 1, by: 0.02, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, value in crownTurned(value) }
        .onAppear {
            ballSide = match.lastPointSide
            crownFocused = true
        }
        .onChange(of: match.log.last?.id) { _, _ in scoreChanged() }
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
        HStack(spacing: 5) {
            Button {
                path.removeLast()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(WatchPalette.raised.opacity(isDimmed ? 0 : 0.9), in: Circle())
            }
            .buttonStyle(WatchPressableStyle())
            .accessibilityLabel("Back")

            // The round label drops out first on small watches; the clock sits on the right.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    courtPill(match)
                    Text(tournament.shortProgressLabel)
                        .font(.watchLabel(.caption2, weight: .bold))
                        .foregroundStyle(WatchPalette.muted)
                        .lineLimit(1)
                        .fixedSize()
                }
                courtPill(match)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .padding(.leading, 8)
        .padding(.trailing, 50)
    }

    private func courtPill(_ match: Match) -> some View {
        HStack(spacing: 4) {
            if !isDimmed { WatchLiveDot(color: WatchPalette.onLime, size: 5) }
            Text("Court \(match.court)")
                .textCase(.uppercase)
                .fixedSize()
        }
        .font(.watchLabel(.caption2, weight: .heavy))
        .foregroundStyle(isDimmed ? WatchPalette.lime : WatchPalette.onLime)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(isDimmed ? Color.clear : WatchPalette.lime, in: Capsule())
        .overlay(Capsule().stroke(WatchPalette.lime, lineWidth: isDimmed ? 1 : 0))
    }

    // MARK: Halves

    private func half(_ side: TeamSide, tournament: Tournament, match: Match, rule: ScoringRule, enabled: Bool, size: CGSize) -> some View {
        let isA = side == .a
        let names = tournament.sideNames(of: match, side)
        let rules = rule.setsRules
        let state = match.sets ?? SetsState()
        // Games/sets: the big figure is the current game point (15, 30, 40, Ad), with
        // games and sets underneath. Rally points: the big figure is the score.
        let bigText = rules.map { state.pointLabel(side, rules: $0) } ?? "\(match.score[side])"
        let detail: String? = rules.map { _ in
            state.completedSets.isEmpty ? String(localized: "Games \(state.games[side])") : String(localized: "G \(state.games[side]) · S \(state.setsWon[side])")
        }
        let tint = isA ? WatchPalette.lime : WatchPalette.chalk
        let scoreSize = max(44, min(size.width * 0.42, size.height * 0.62))
        let hits = isA ? hitsA : hitsB
        let doubleTap = model.doubleTapSide(for: match.id) == side

        return Button {
            score(side, match: match, rule: rule)
        } label: {
            VStack(spacing: 0) {
                VStack(spacing: -1) {
                    ForEach(names, id: \.self) { name in
                        Text(name)
                            .font(.watchLabel(.caption, weight: .bold))
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .foregroundStyle(isDimmed ? tint.opacity(0.7) : tint.opacity(0.9))
                .overlay(alignment: isA ? .topLeading : .topTrailing) {
                    if doubleTap && !isDimmed {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tint)
                            .offset(x: isA ? -10 : 10, y: 1)
                            .accessibilityHidden(true)
                    }
                }
                Spacer(minLength: 0)
                Text(bigText)
                    .font(.watchScore(scoreSize, weight: isDimmed ? .semibold : .heavy))
                    .foregroundStyle(isDimmed ? tint.opacity(0.85) : tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.vertical, -scoreSize * 0.08)
                    .contentTransition(.numericText(value: Double(isA ? match.score.a : match.score.b)))
                    .shadow(color: isDimmed ? .clear : tint.opacity(0.35), radius: 8)
                    .keyframeAnimator(initialValue: 1.0, trigger: hits) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        KeyframeTrack {
                            SpringKeyframe(reduceMotion || isDimmed ? 1.0 : 1.18, duration: 0.12, spring: .snappy)
                            SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                        }
                    }
                if let detail {
                    Text(detail)
                        .font(.watchLabel(.caption2, weight: .bold).monospacedDigit())
                        .foregroundStyle(tint.opacity(0.7))
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background {
                if !isDimmed {
                    HalfFlash(side: side, trigger: hits, reduceMotion: reduceMotion)
                }
            }
        }
        .buttonStyle(WatchPressableStyle(scale: 0.97))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
        .animation(WatchMotion.resolve(WatchMotion.pop, reduceMotion: reduceMotion), value: bigText)
        .doubleTapShortcut(doubleTap && enabled)
        .accessibilityLabel(rules == nil
            ? String(localized: "Point for \(names.joined(separator: String(localized: " and "))). Score \(bigText).")
            : String(localized: "Point for \(names.joined(separator: String(localized: " and "))). Points \(bigText)."))
        .accessibilityIdentifier(isA ? "watchPointA" : "watchPointB")
    }

    /// The ball rests on the side that won the last point and arcs over the net to the
    /// side that wins the next one.
    private func ball(in size: CGSize) -> some View {
        let restY = size.height - 8
        let x: CGFloat = switch ballSide {
        case .a: size.width * 0.5 - 16
        case .b: size.width * 0.5 + 16
        case nil: size.width * 0.5
        }
        return BallFlight(trigger: flights, reduceMotion: reduceMotion)
            .position(x: x, y: restY)
            .animation(WatchMotion.resolve(WatchMotion.flight, reduceMotion: reduceMotion), value: ballSide)
            .allowsHitTesting(false)
    }

    // MARK: Footer

    private func footer(_ tournament: Tournament, _ match: Match, rule: ScoringRule, awaiting: Bool, callout: WatchScoreCallout?) -> some View {
        let canUndo = ScoringEngine.lastUndoableEvent(in: match) != nil
        return HStack(spacing: 6) {
            Button {
                undo(match)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 34)
                    .background(WatchPalette.raised.opacity(isDimmed ? 0 : 0.95), in: Capsule())
                    .overlay {
                        Capsule()
                            .trim(from: 0, to: abs(crown))
                            .stroke(WatchPalette.lime, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .opacity(crown == 0 ? 0 : 1)
                    }
                    .scaleEffect(1 + abs(crown) * 0.12)
            }
            .buttonStyle(WatchPressableStyle())
            .disabled(!canUndo)
            .opacity(isDimmed ? 0 : 1)
            .accessibilityLabel("Undo last point")

            Group {
                if awaiting {
                    Button {
                        confirmFinish = true
                    } label: {
                        Text(rule.isSets ? "Finish match" : "Finish \(match.score.a)–\(match.score.b)")
                            .font(.watchLabel(.footnote, weight: .heavy))
                            .foregroundStyle(WatchPalette.onLime)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(WatchPalette.lime, in: Capsule())
                            .background {
                                if !reduceMotion && !isDimmed { FinishGlow() }
                            }
                    }
                    .buttonStyle(WatchPressableStyle())
                    .doubleTapShortcut(true)
                    .accessibilityIdentifier("watchFinish")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else if let callout {
                    CalloutPill(callout: callout)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                } else {
                    ProgressStatus(match: match, rule: rule, dimmed: isDimmed)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(WatchMotion.resolve(WatchMotion.pop, reduceMotion: reduceMotion), value: awaiting)
            .animation(WatchMotion.resolve(WatchMotion.pop, reduceMotion: reduceMotion), value: callout)

            Button {
                showActions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 34)
                    .background(WatchPalette.raised.opacity(isDimmed ? 0 : 0.95), in: Capsule())
                    .overlay(alignment: .topTrailing) {
                        WatchSyncBadge(status: store.syncStatus)
                            .offset(x: 4, y: -6)
                    }
            }
            .buttonStyle(WatchPressableStyle())
            .opacity(isDimmed ? 0 : 1)
            .accessibilityLabel("Match actions")
        }
    }

    // MARK: Actions

    private func score(_ side: TeamSide, match before: Match, rule: ScoringRule) {
        guard store.recordPoint(side, match: before.id, tournament: tournamentID) else {
            WatchHaptics.failure()
            return
        }
        let after = store.state.tournament(tournamentID)?.match(matchID)
        if let after, Self.isMilestone(before: before, after: after, rule: rule) {
            WatchHaptics.milestone()
        } else {
            WatchHaptics.point()
        }
    }

    private func undo(_ match: Match) {
        if store.undo(match: match.id, tournament: tournamentID) {
            WatchHaptics.undo()
            undoToast += 1
        } else {
            WatchHaptics.failure()
        }
    }

    /// Animates whatever changed the log: our tap, an undo, or a point from the iPhone.
    private func scoreChanged() {
        guard let match = store.state.tournament(tournamentID)?.match(matchID) else { return }
        if case .point(let side)? = match.log.last?.kind {
            if side == .a { hitsA += 1 } else { hitsB += 1 }
        }
        let side = match.lastPointSide
        if side != ballSide { flights += 1 }
        ballSide = side
    }

    private func crownTurned(_ value: Double) {
        crownIdle?.cancel()
        guard value != 0 else { return }
        if abs(value) >= 0.98 {
            crown = 0
            if let match = store.state.tournament(tournamentID)?.match(matchID),
               ScoringEngine.lastUndoableEvent(in: match) != nil, !match.isCompleted {
                undo(match)
            }
            return
        }
        crownIdle = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            withAnimation(WatchMotion.settle) { crown = 0 }
        }
    }

    /// A game, a set or the whole match was won with this point.
    static func isMilestone(before: Match, after: Match, rule: ScoringRule) -> Bool {
        if ScoringEngine.isDecided(after, rule: rule) { return true }
        guard rule.isSets else { return false }
        let old = before.sets ?? SetsState(), new = after.sets ?? SetsState()
        return new.games != old.games || new.completedSets.count != old.completedSets.count
    }
}

// MARK: - Callouts

/// The big moments of a match, announced over the court.
struct WatchScoreCallout: Equatable {
    enum Kind: Equatable { case matchWon, matchPoint, setPoint, lastPoint, golden, deuce, tieBreak }
    let kind: Kind
    let text: String

    var tint: Color {
        switch kind {
        case .matchWon, .matchPoint, .lastPoint: WatchPalette.lime
        case .setPoint, .tieBreak: WatchPalette.chalk
        case .golden: WatchPalette.gold
        case .deuce: WatchPalette.chalk
        }
    }

    init?(match: Match, rule: ScoringRule, awaiting: Bool) {
        if awaiting {
            kind = .matchWon
            text = String(localized: "Match won")
            return
        }
        if let rules = rule.setsRules {
            let state = match.sets ?? SetsState()
            var setPoint = false
            for side in [TeamSide.a, .b] {
                var next = state
                next.pointWon(by: side, rules: rules)
                if next.winner != nil {
                    kind = .matchPoint
                    text = String(localized: "Match point")
                    return
                }
                if next.completedSets.count > state.completedSets.count { setPoint = true }
            }
            if setPoint {
                kind = .setPoint
                text = String(localized: "Set point")
                return
            }
            guard let situation = state.situation(rules: rules) else { return nil }
            text = situation
            if state.inTieBreak {
                kind = .tieBreak
            } else {
                kind = rules.goldenPoint ? .golden : .deuce
            }
            return
        }
        if let total = rule.totalPoints, total > 1, match.score.total == total - 1 {
            kind = .lastPoint
            text = String(localized: "Last point")
            return
        }
        return nil
    }
}

/// Persistent pill in the footer while the moment lasts.
private struct CalloutPill: View {
    let callout: WatchScoreCallout

    var body: some View {
        Text(callout.text)
            .font(.watchLabel(.footnote, weight: .heavy))
            .textCase(.uppercase)
            .foregroundStyle(WatchPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(callout.tint, in: Capsule())
            .shadow(color: callout.tint.opacity(0.5), radius: 6)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// When a moment starts, its name sweeps across the net like a broadcast graphic.
private struct CalloutSweep: View {
    let callout: WatchScoreCallout?
    let reduceMotion: Bool
    @State private var shown: WatchScoreCallout?
    @State private var sweeps = 0

    var body: some View {
        GeometryReader { proxy in
            if let shown, !reduceMotion {
                Text(shown.text)
                    .font(.watchLabel(.title3, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(WatchPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 12)
                    .frame(width: proxy.size.width, height: 34)
                    .background(shown.tint)
                    .keyframeAnimator(initialValue: SweepValue(), trigger: sweeps) { content, value in
                        content
                            .offset(x: value.x * proxy.size.width)
                            .opacity(value.opacity)
                            .rotationEffect(.degrees(-4))
                    } keyframes: { _ in
                        KeyframeTrack(\.x) {
                            CubicKeyframe(-1.1, duration: 0.01)
                            SpringKeyframe(0, duration: 0.35, spring: .snappy)
                            LinearKeyframe(0, duration: 0.6)
                            CubicKeyframe(1.1, duration: 0.3)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(1, duration: 0.01)
                            LinearKeyframe(1, duration: 1.2)
                            LinearKeyframe(0, duration: 0.05)
                        }
                    }
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.52)
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: callout) { old, new in
            guard let new, new.kind != old?.kind else { return }
            shown = new
            sweeps += 1
        }
    }

    struct SweepValue {
        var x: Double = -1.1
        var opacity: Double = 0
    }
}

/// Points progress ("20/24" over a lime rail), the set line, or "Timed".
private struct ProgressStatus: View {
    let match: Match
    let rule: ScoringRule
    let dimmed: Bool

    var body: some View {
        if let total = rule.totalPoints {
            let progress = min(1, Double(match.score.total) / Double(max(1, total)))
            VStack(spacing: 3) {
                Text(verbatim: "\(match.score.total)/\(total)")
                    .font(.watchLabel(.caption2, weight: .heavy).monospacedDigit())
                    .foregroundStyle(WatchPalette.chalk.opacity(0.85))
                    .contentTransition(.numericText(value: Double(match.score.total)))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WatchPalette.chalk.opacity(0.15))
                        Capsule().fill(WatchPalette.lime)
                            .frame(width: max(4, proxy.size.width * progress))
                    }
                }
                .frame(height: 4)
                .opacity(dimmed ? 0.5 : 1)
            }
            .padding(.horizontal, 6)
            .animation(WatchMotion.settle, value: progress)
        } else {
            Text(text)
                .font(.watchLabel(.caption2, weight: .heavy).monospacedDigit())
                .foregroundStyle(WatchPalette.chalk.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
    }

    private var text: String {
        if let rules = rule.setsRules {
            let state = match.sets ?? SetsState()
            return state.situation(rules: rules) ?? (state.summary().isEmpty ? "0-0" : state.summary())
        }
        return String(localized: "Timed")
    }
}

/// Breathing glow behind the Finish button.
private struct FinishGlow: View {
    var body: some View {
        Capsule()
            .fill(WatchPalette.lime)
            .phaseAnimator([false, true]) { content, expanded in
                content
                    .scaleEffect(x: expanded ? 1.08 : 1, y: expanded ? 1.3 : 1)
                    .opacity(expanded ? 0 : 0.6)
            } animation: { expanded in
                expanded ? .easeOut(duration: 1.1) : .easeIn(duration: 0.2)
            }
            .accessibilityHidden(true)
    }
}

/// "Point undone" slides up for a moment after an undo.
private struct UndoToast: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "arrow.uturn.backward")
                Text("Point undone")
            }
            .font(.watchLabel(.footnote, weight: .heavy))
            .foregroundStyle(WatchPalette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(WatchPalette.chalk, in: Capsule())
            .keyframeAnimator(initialValue: ToastValue(), trigger: trigger) { content, value in
                content
                    .offset(y: value.y)
                    .opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.y) {
                    SpringKeyframe(reduceMotion ? 0 : -44, duration: 0.3, spring: .snappy)
                    LinearKeyframe(reduceMotion ? 0 : -44, duration: 1.0)
                    CubicKeyframe(reduceMotion ? 0 : 20, duration: 0.25)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.15)
                    LinearKeyframe(1, duration: 1.15)
                    LinearKeyframe(0, duration: 0.25)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    struct ToastValue {
        var y: Double = 30
        var opacity: Double = 0
    }
}

// MARK: - Court

/// The court drawn under the score: two halves, service lines, a glowing net. In Always
/// On it collapses to faint lines on black.
struct WatchCourtSurface: View {
    let dimmed: Bool
    /// When the match is won, the winner's half glows.
    var winner: TeamSide?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.black
                if !dimmed {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [WatchPalette.lime.opacity(0.2), WatchPalette.turf.opacity(0.9)], startPoint: .topLeading, endPoint: .bottom)
                            .overlay { winnerGlow(.a) }
                        LinearGradient(colors: [WatchPalette.chalk.opacity(0.12), WatchPalette.turf.opacity(0.9)], startPoint: .topTrailing, endPoint: .bottom)
                            .overlay { winnerGlow(.b) }
                    }
                }
                WatchCourtLines()
                    .stroke(WatchPalette.chalk.opacity(dimmed ? 0.1 : 0.14), lineWidth: 1)
                // The net.
                Rectangle()
                    .fill(WatchPalette.chalk.opacity(dimmed ? 0.25 : 0.5))
                    .frame(width: 1.5, height: size.height)
                    .overlay {
                        Rectangle()
                            .stroke(WatchPalette.chalk.opacity(dimmed ? 0 : 0.35), style: StrokeStyle(lineWidth: 5, dash: [1.5, 3]))
                    }
                    .shadow(color: dimmed ? .clear : WatchPalette.lime.opacity(0.5), radius: 4)
                    .position(x: size.width / 2, y: size.height / 2)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func winnerGlow(_ side: TeamSide) -> some View {
        if winner == side {
            RadialGradient(colors: [(side == .a ? WatchPalette.lime : WatchPalette.chalk).opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 120)
                .phaseAnimator(reduceMotion ? [true] : [false, true]) { content, bright in
                    content.opacity(bright ? 1 : 0.45)
                } animation: { _ in .easeInOut(duration: 0.9) }
        }
    }
}

/// Service lines and the centre service line, seen from above with the net vertical.
struct WatchCourtLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let serviceOffset = rect.width * 0.31
        let left = rect.midX - serviceOffset, right = rect.midX + serviceOffset
        path.move(to: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY))
        path.move(to: CGPoint(x: right, y: rect.minY))
        path.addLine(to: CGPoint(x: right, y: rect.maxY))
        path.move(to: CGPoint(x: left, y: rect.midY))
        path.addLine(to: CGPoint(x: right, y: rect.midY))
        return path
    }
}

/// A burst of light from the middle of the half that just won a point.
private struct HalfFlash: View {
    let side: TeamSide
    let trigger: Int
    let reduceMotion: Bool

    var body: some View {
        RadialGradient(
            colors: [(side == .a ? WatchPalette.lime : WatchPalette.chalk).opacity(0.55), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 110
        )
        .keyframeAnimator(initialValue: FlashValue(), trigger: trigger) { content, value in
            content
                .opacity(value.opacity)
                .scaleEffect(value.scale)
        } keyframes: { _ in
            KeyframeTrack(\.opacity) {
                LinearKeyframe(reduceMotion ? 0.35 : 1, duration: 0.06)
                CubicKeyframe(0, duration: reduceMotion ? 0.3 : 0.75)
            }
            KeyframeTrack(\.scale) {
                LinearKeyframe(0.4, duration: 0.01)
                SpringKeyframe(reduceMotion ? 0.4 : 1.4, duration: 0.6, spring: .smooth)
            }
        }
        .allowsHitTesting(false)
    }

    struct FlashValue {
        var opacity: Double = 0
        var scale: Double = 1
    }
}

/// The ball with its shadow; on each trigger it lifts, arcs and bounces on landing.
private struct BallFlight: View {
    let trigger: Int
    let reduceMotion: Bool

    var body: some View {
        WatchBall(size: 13)
            .keyframeAnimator(initialValue: ArcValue(), trigger: trigger) { content, value in
                ZStack {
                    Ellipse()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 14 * (1 - min(0.6, abs(value.lift) / 80)), height: 4)
                        .offset(y: 8)
                    content
                        .scaleEffect(x: value.scale * value.squash, y: value.scale / value.squash)
                        .offset(y: value.lift)
                }
            } keyframes: { _ in
                // Under Reduce Motion the ball slides without lifting or bouncing.
                let motion = reduceMotion ? 0.0 : 1.0
                KeyframeTrack(\.lift) {
                    CubicKeyframe(-52 * motion, duration: 0.22)
                    CubicKeyframe(0, duration: 0.22)
                    CubicKeyframe(-10 * motion, duration: 0.1)
                    CubicKeyframe(0, duration: 0.1)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1 + 0.5 * motion, duration: 0.22)
                    CubicKeyframe(1, duration: 0.22)
                }
                KeyframeTrack(\.squash) {
                    LinearKeyframe(1, duration: 0.42)
                    SpringKeyframe(1 + 0.35 * motion, duration: 0.06, spring: .snappy)
                    SpringKeyframe(1, duration: 0.25, spring: .bouncy)
                }
            }
    }

    struct ArcValue {
        var lift: Double = 0
        var scale: Double = 1
        var squash: Double = 1
    }
}

// MARK: - Helpers

extension Match {
    /// The side that won the last point still counted (undone points are skipped; a
    /// manual score change resets it).
    var lastPointSide: TeamSide? {
        var undone = Set<EventID>()
        for event in log.reversed() {
            switch event.kind {
            case .undo(let target):
                undone.insert(target)
            case .point(let side):
                if !undone.contains(event.id) { return side }
            case .setScore, .setSets:
                if !undone.contains(event.id) { return nil }
            case .finish, .reopen:
                continue
            }
        }
        return nil
    }
}

extension View {
    /// Double Tap (watchOS 11+) triggers this button.
    @ViewBuilder
    func doubleTapShortcut(_ enabled: Bool) -> some View {
        if #available(watchOS 11.0, *) {
            handGestureShortcut(.primaryAction, isEnabled: enabled)
        } else {
            self
        }
    }
}

// MARK: - Actions sheet

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
            .disabled(!ScoringEngine.canFinish(match, rule: tournament.scoringRule(for: match)))
            .foregroundStyle(WatchPalette.lime)

            Button {
                dismiss()
                path = [.courts(tournament.id)]
            } label: {
                Label("Switch Court", systemImage: "square.grid.2x2")
            }

            if #available(watchOS 11.0, *) {
                Section("Double Tap") {
                    ForEach([TeamSide.a, .b], id: \.self) { side in
                        doubleTapRow(side)
                    }
                    Button {
                        model.setDoubleTapSide(nil, for: match.id)
                    } label: {
                        HStack {
                            Text("Off")
                            Spacer()
                            if model.doubleTapSide(for: match.id) == nil {
                                Image(systemName: "checkmark").foregroundStyle(WatchPalette.lime)
                            }
                        }
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tournament.sideNames(of: match, .a).joined(separator: " & "))
                        .font(.caption2)
                        .foregroundStyle(WatchPalette.lime)
                    Text("vs").font(.caption2).foregroundStyle(WatchPalette.muted)
                    Text(tournament.sideNames(of: match, .b).joined(separator: " & ")).font(.caption2)
                }
            }
        }
        .navigationTitle("Match")
    }

    private func doubleTapRow(_ side: TeamSide) -> some View {
        Button {
            model.setDoubleTapSide(side, for: match.id)
            dismiss()
        } label: {
            HStack {
                Image(systemName: "hand.tap.fill")
                    .foregroundStyle(side == .a ? WatchPalette.lime : WatchPalette.chalk)
                    .accessibilityHidden(true)
                Text("+1 \(tournament.sideNames(of: match, side).joined(separator: " & "))")
                    .lineLimit(2)
                Spacer(minLength: 0)
                if model.doubleTapSide(for: match.id) == side {
                    Image(systemName: "checkmark").foregroundStyle(WatchPalette.lime)
                }
            }
        }
    }
}
