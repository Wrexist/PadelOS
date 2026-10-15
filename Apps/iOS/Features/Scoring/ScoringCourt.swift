import SwiftUI
import PadelCore

/// The scoring court: the two halves of a padel court seen from above, net in the
/// middle. Tap a team's half to give it the point (the ball flies to that side), pull the
/// court down to undo the last point (it resists like a rubber band and clicks when it
/// will undo), hold a half to enter a result. Team A is lime, Team B graphite, in both
/// colour schemes, so the court reads the same from two metres away in any light.
///
/// VoiceOver sees two buttons, "Point for Team A" and "Point for Team B", each with the
/// team's names and score as its value and "Undo" / "Enter Result" as extra actions.
struct ScoringCourt: View {
    struct Side {
        var names: [String]
        /// What the big numeral shows: points, or 0/15/30/40/Ad.
        var score: String
        /// Numeric value for the rolling-digit transition, when the score is a number.
        var numeric: Double?
        /// Small line under the score (games won in the current set).
        var detail: String?
    }

    let a: Side
    let b: Side
    /// "Golden point", "Deuce", "Tie-break"…
    var situation: String?
    var canScore: Bool
    var canUndo: Bool
    var winner: TeamSide?
    var isFinished: Bool
    var hapticsEnabled: Bool
    var onPoint: (TeamSide) -> Void
    var onUndo: () -> Void
    var onEnterResult: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var ball = BallTrigger()
    @State private var pull: CGFloat = 0
    @State private var armed = false
    @State private var undoCount = 0
    @State private var unfolded = false

    struct BallTrigger: Equatable {
        var count = 0
        var side: TeamSide = .a
    }

    private static let undoThreshold: CGFloat = 110

    /// Team A sits on the leading side: left, or right in right-to-left languages. The
    /// court itself is laid out left to right so the ball's flight is physical.
    private var leftSide: TeamSide { layoutDirection == .rightToLeft ? .b : .a }

    var body: some View {
        ZStack(alignment: .top) {
            pullHint
            GeometryReader { proxy in
                ZStack {
                    HStack(spacing: 0) {
                        half(leftSide, isLeft: true)
                        half(leftSide.opposite, isLeft: false)
                    }
                    net
                    ballView(width: proxy.size.width)
                    if let situation, !isFinished {
                        SituationBadge(text: situation)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, Theme.Spacing.m)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: Theme.Colors.accent.opacity(isFinished ? 0 : 0.18), radius: 30, y: 12)
            }
            .offset(y: pull)
            .scaleEffect(1 - pull / 1800, anchor: .top)
            .simultaneousGesture(pullGesture)
        }
        .animation(Motion.bouncy, value: situation)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: ball) { _, _ in hapticsEnabled }
        .sensoryFeedback(.selection, trigger: armed) { _, _ in hapticsEnabled }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: undoCount) { _, _ in hapticsEnabled }
        .onAppear {
            withAnimation((reduceMotion ? Motion.fade : Motion.hero).delay(0.08)) { unfolded = true }
        }
    }

    // MARK: Halves

    private func half(_ side: TeamSide, isLeft: Bool) -> some View {
        CourtHalf(
            side: side,
            model: side == .a ? a : b,
            isLeft: isLeft,
            isInteractive: canScore,
            isWinner: winner == side,
            isLoser: winner == side.opposite,
            contentDirection: layoutDirection,
            onTap: { score(side) },
            onLongPress: onEnterResult,
            onUndo: canUndo ? { undo() } : nil
        )
        .rotation3DEffect(
            .degrees(unfolded || reduceMotion ? 0 : (isLeft ? 70 : -70)),
            axis: (x: 0, y: 1, z: 0),
            anchor: isLeft ? .trailing : .leading,
            perspective: 0.6
        )
        .opacity(unfolded ? 1 : 0.01)
    }

    private func score(_ side: TeamSide) {
        guard canScore else { return }
        onPoint(side)
        ball = BallTrigger(count: ball.count + 1, side: side)
    }

    private func undo() {
        guard canUndo else { return }
        onUndo()
        undoCount += 1
    }

    // MARK: Net and ball

    private var net: some View {
        ZStack {
            Rectangle()
                .fill(Theme.Colors.ink)
                .frame(width: 6)
            Rectangle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 2)
                .mask {
                    VStack(spacing: 5) {
                        ForEach(0..<60, id: \.self) { _ in Rectangle().frame(height: 6) }
                    }
                }
        }
        .accessibilityHidden(true)
    }

    private struct BallFlight {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var scale: CGFloat = 1
        var opacity: Double = 1
    }

    private func ballView(width: CGFloat) -> some View {
        let toLeft = ball.side == leftSide
        let dx = (toLeft ? -1 : 1) * width * 0.25
        return Circle()
            .fill(RadialGradient(colors: [.white, Color(hex: 0xE9F7C8)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 14))
            .frame(width: 24, height: 24)
            .shadow(color: Theme.Colors.accent.opacity(0.8), radius: 10)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
            .keyframeAnimator(initialValue: BallFlight(), trigger: ball) { content, value in
                content
                    .scaleEffect(value.scale)
                    .offset(x: value.x, y: value.y)
                    .opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    CubicKeyframe(dx, duration: 0.45)
                    LinearKeyframe(dx, duration: 0.25)
                    LinearKeyframe(0, duration: 0.01)
                }
                KeyframeTrack(\.y) {
                    CubicKeyframe(-110, duration: 0.22)
                    CubicKeyframe(0, duration: 0.23)
                    CubicKeyframe(-22, duration: 0.1)
                    CubicKeyframe(0, duration: 0.1)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.5, duration: 0.22)
                    CubicKeyframe(1, duration: 0.23)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.55)
                    LinearKeyframe(0, duration: 0.15)
                    LinearKeyframe(0, duration: 0.03)
                    LinearKeyframe(1, duration: 0.25)
                }
            }
            .opacity(reduceMotion || isFinished ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Pull to undo

    private var pullGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                let dy = value.translation.height
                guard canUndo, dy > 0, abs(dy) > abs(value.translation.width) else {
                    if pull != 0 { pull = 0 }
                    if armed { armed = false }
                    return
                }
                pull = Self.rubberBand(dy)
                let shouldArm = dy > Self.undoThreshold
                if shouldArm != armed { armed = shouldArm }
            }
            .onEnded { _ in
                if armed { undo() }
                armed = false
                withAnimation(reduceMotion ? Motion.fade : Motion.bouncy) { pull = 0 }
            }
    }

    /// Movement that gets harder the further you pull.
    private static func rubberBand(_ distance: CGFloat) -> CGFloat {
        let limit: CGFloat = 200
        return (1 - 1 / (distance * 0.55 / limit + 1)) * limit
    }

    private var pullHint: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.title3)
                .rotationEffect(.degrees(armed ? -360 : 0))
                .animation(Motion.bouncy, value: armed)
            Text(armed ? "Release to undo" : "Pull down to undo")
                .font(.padelMeta.weight(.bold))
                .contentTransition(.opacity)
        }
        .foregroundStyle(armed ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(armed ? Theme.Colors.accent : Theme.Colors.surfaceRaised, in: Capsule())
        .scaleEffect(armed ? 1.06 : 1)
        .opacity(Double(min(1, pull / 60)))
        .padding(.top, 4)
        .animation(Motion.snappy, value: armed)
        .accessibilityHidden(true)
    }
}

// MARK: - One half

private struct CourtHalf: View {
    let side: TeamSide
    let model: ScoringCourt.Side
    let isLeft: Bool
    let isInteractive: Bool
    let isWinner: Bool
    let isLoser: Bool
    /// The app's layout direction, restored for the text inside the half.
    let contentDirection: LayoutDirection
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onUndo: (() -> Void)?

    @State private var ripples: [Ripple] = []
    @State private var pressed = false
    @State private var bump = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Ripple: Identifiable {
        let id = UUID()
        let location: CGPoint
    }

    private var isA: Bool { side == .a }
    private var ink: Color { isA ? Theme.Colors.ink : .white }
    private var softInk: Color { isA ? Theme.Colors.ink.opacity(0.62) : Theme.Colors.onDarkSecondary }

    var body: some View {
        GeometryReader { proxy in
            let numeral = min(proxy.size.width * 0.8, proxy.size.height * 0.4)
            ZStack {
                background
                markings
                ForEach(ripples) { ripple in
                    ScoreRipple(color: isA ? Theme.Colors.ink.opacity(0.4) : Theme.Colors.accent.opacity(0.8))
                        .position(ripple.location)
                }
                VStack(spacing: Theme.Spacing.s) {
                    names
                    Spacer(minLength: 0)
                    Text(verbatim: model.score)
                        .font(.padelScoreboard(size: numeral))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.35)
                        .contentTransition(model.numeric.map { ContentTransition.numericText(value: $0) } ?? ContentTransition.numericText())
                        .keyframeAnimator(initialValue: CGFloat(1), trigger: bump) { content, scale in
                            content.scaleEffect(scale)
                        } keyframes: { _ in
                            KeyframeTrack {
                                CubicKeyframe(1.16, duration: 0.1)
                                SpringKeyframe(1, duration: 0.4, spring: .bouncy)
                            }
                        }
                        .shadow(color: isA ? .clear : Theme.Colors.accent.opacity(0.25), radius: 18)
                        .animation(Motion.snappy, value: model.score)
                    if let detail = model.detail {
                        Text(verbatim: detail)
                            .font(.padelEyebrow)
                            .textCase(.uppercase)
                            .foregroundStyle(softInk)
                    }
                    Spacer(minLength: 0)
                    footer
                }
                .padding(Theme.Spacing.l)
                .environment(\.layoutDirection, contentDirection)
                if isLoser {
                    Color.black.opacity(0.35)
                }
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(Motion.snappy, value: pressed)
        .onTapGesture(coordinateSpace: .local) { location in
            guard isInteractive else { return }
            addRipple(at: location)
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.6, maximumDistance: 14, perform: {
            guard isInteractive else { return }
            onLongPress()
        }, onPressingChanged: { isPressing in
            pressed = isPressing && isInteractive
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Point for Team \(isA ? "A" : "B")"))
        .accessibilityValue(Text(verbatim: "\(model.names.joined(separator: String(localized: " and "))), \(model.score)"))
        .accessibilityAddTraits(isInteractive ? .isButton : [])
        .accessibilityAction {
            guard isInteractive else { return }
            onTap()
        }
        .accessibilityAction(named: Text("Enter Result")) { onLongPress() }
        .accessibilityActions {
            if let onUndo {
                Button("Undo", action: onUndo)
            }
        }
        .accessibilityIdentifier(isA ? "pointTeamA" : "pointTeamB")
    }

    private var background: some View {
        ZStack {
            if isA {
                LinearGradient(colors: [Theme.Colors.limeBright, Theme.Colors.accent, Theme.Colors.limeDeep], startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [Theme.Colors.graphiteRaised, Theme.Colors.graphite, Color(hex: 0x131613)], startPoint: .top, endPoint: .bottom)
            }
            if isWinner {
                RadialGradient(colors: [Color.white.opacity(isA ? 0.45 : 0.12), .clear], center: .center, startRadius: 10, endRadius: 260)
            }
        }
    }

    /// Service line and centre service line of this half.
    private var markings: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Path { path in
                let serviceX = isLeft ? size.width * 0.42 : size.width * 0.58
                path.move(to: CGPoint(x: serviceX, y: 0))
                path.addLine(to: CGPoint(x: serviceX, y: size.height))
                let netX = isLeft ? size.width : 0
                path.move(to: CGPoint(x: serviceX, y: size.height / 2))
                path.addLine(to: CGPoint(x: netX, y: size.height / 2))
            }
            .stroke(isA ? Theme.Colors.ink.opacity(0.1) : Color.white.opacity(0.07), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.names.enumerated()), id: \.offset) { _, name in
                Text(verbatim: name)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var footer: some View {
        if isWinner {
            Image(systemName: "trophy.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(ink)
                .symbolEffect(.bounce, value: isWinner)
                .accessibilityHidden(true)
        } else if isInteractive {
            Text("+1")
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .foregroundStyle(isA ? Theme.Colors.ink : Theme.Colors.accent)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .background(isA ? Theme.Colors.ink.opacity(0.1) : Theme.Colors.accent.opacity(0.14), in: Capsule())
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: 30)
        }
    }

    private func addRipple(at location: CGPoint) {
        let ripple = Ripple(location: location)
        guard !reduceMotion else { return }
        ripples.append(ripple)
        bump += 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            ripples.removeAll { $0.id == ripple.id }
        }
    }
}

/// "GOLDEN POINT", "DEUCE", "TIE-BREAK" over the net.
private struct SituationBadge: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing = false

    var body: some View {
        Text(verbatim: text)
            .font(.padelEyebrow)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 7)
            .background(Theme.Colors.ink, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Colors.accent, lineWidth: 1.5))
            .shadow(color: Theme.Colors.accent.opacity(glowing ? 0.9 : 0.3), radius: glowing ? 14 : 6)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: glowing)
            .onAppear { glowing = true }
            .accessibilityHidden(true)
    }
}
