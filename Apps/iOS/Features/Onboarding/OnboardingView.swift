import SwiftUI

/// First-launch introduction. Always dark (the brand look), five pages with native,
/// shape-based illustrations that animate when their page becomes active. With Reduce
/// Motion every animation is replaced by a static frame or a cross-fade.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private static let pageCount = 5

    var body: some View {
        ZStack {
            OnboardingBackground(page: page)
            VStack(spacing: 0) {
                topBar
                TabView(selection: $page) {
                    OnboardingPage(
                        isActive: page == 0,
                        title: "Padel nights,\nperfectly run.",
                        subtitle: "Create a tournament in under a minute. Fair schedules, live scores and standings — all in one place."
                    ) { active in WelcomeIllustration(isActive: active) }
                        .tag(0)
                    OnboardingPage(
                        isActive: page == 1,
                        title: "Fair rotations,\nevery round.",
                        subtitle: "Americano, Mexicano, team formats, King of the Court and playoffs. Partners, opponents and rests are balanced for you."
                    ) { active in RotationIllustration(isActive: active) }
                        .tag(1)
                    OnboardingPage(
                        isActive: page == 2,
                        title: "Score from\nyour wrist.",
                        subtitle: "One tap per point on Apple Watch. It keeps scoring even when your iPhone stays in the bag."
                    ) { active in WatchIllustration(isActive: active) }
                        .tag(2)
                    OnboardingPage(
                        isActive: page == 3,
                        title: "Live on your\nLock Screen.",
                        subtitle: "Follow the score in the Dynamic Island and add points without unlocking your iPhone."
                    ) { active in LockScreenIllustration(isActive: active) }
                        .tag(3)
                    OnboardingPage(
                        isActive: page == 4,
                        title: "Ready when\nyou are.",
                        subtitle: "No account. No ads. Works offline. Your tournaments stay on your devices."
                    ) { active in PromisesIllustration(isActive: active) }
                        .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .accessibilityIdentifier("onboardingPages")

                PageIndicator(count: Self.pageCount, current: page)
                    .padding(.bottom, Theme.Spacing.l)

                Button(action: advance) {
                    Text(page == Self.pageCount - 1 ? "Get Started" : "Continue")
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: page)
                }
                .buttonStyle(.padelPrimary)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.l)
                .accessibilityIdentifier(page == Self.pageCount - 1 ? "onboardingGetStarted" : "onboardingContinue")
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.selection, trigger: page)
    }

    private var topBar: some View {
        HStack {
            BrandMark()
            Spacer()
            if page < Self.pageCount - 1 {
                Button("Skip", action: onFinish)
                    .font(.padelButton)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
                    .accessibilityIdentifier("onboardingSkip")
                    .transition(.opacity)
            }
        }
        .frame(minHeight: Theme.minimumTapTarget)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.s)
        .animation(.easeInOut(duration: 0.2), value: page)
    }

    private func advance() {
        if page < Self.pageCount - 1 {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.9)) {
                page += 1
            }
        } else {
            onFinish()
        }
    }
}

// MARK: - Page scaffold

/// Illustration on top, title and subtitle below, revealed with a short stagger each
/// time the page becomes active.
private struct OnboardingPage<Illustration: View>: View {
    let isActive: Bool
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder let illustration: (Bool) -> Illustration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: 0)
            illustration(isActive)
                .frame(height: 300)
                .accessibilityHidden(true)
            VStack(spacing: Theme.Spacing.m) {
                Text(title)
                    .font(.system(size: 34, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .reveal(revealed, delay: 0.05, reduceMotion: reduceMotion)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .reveal(revealed, delay: 0.15, reduceMotion: reduceMotion)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                revealed = false
                withAnimation { revealed = true }
            }
        }
    }
}

private extension View {
    /// Fade and rise in; a plain fade with Reduce Motion.
    func reveal(_ shown: Bool, delay: Double, reduceMotion: Bool) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .animation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.85).delay(delay), value: shown)
    }
}

/// Dots that stretch into a capsule for the current page.
private struct PageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Theme.Colors.accent : Color.white.opacity(0.25))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: current)
        .accessibilityElement()
        .accessibilityLabel(Text("Page \(current + 1) of \(count)"))
    }
}

/// Graphite with faint court lines and a lime glow that drifts between pages.
private struct OnboardingBackground: View {
    let page: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                Color(hex: 0x101210)
                RadialGradient(
                    colors: [Theme.Colors.accent.opacity(0.22), .clear],
                    center: .center, startRadius: 0, endRadius: width * 0.8
                )
                .frame(width: width * 1.6, height: width * 1.6)
                .offset(x: CGFloat(page - 2) * width * 0.22, y: -proxy.size.height * 0.18)
                .blur(radius: 30)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: page)
                CourtGrid()
                    .stroke(Color.white.opacity(0.035), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
    }
}

private struct CourtGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 44
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += step
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += step
        }
        return path
    }
}

// MARK: - Shared drawing

/// Top-down padel court: outline, net, service lines and centre lines.
struct PadelCourtShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 6)
        let midY = rect.midY
        let serviceOffset = rect.height * 0.15
        path.move(to: CGPoint(x: rect.minX, y: midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: midY))
        for y in [midY - serviceOffset * 2, midY + serviceOffset * 2] {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        path.move(to: CGPoint(x: rect.midX, y: midY - serviceOffset * 2))
        path.addLine(to: CGPoint(x: rect.midX, y: midY + serviceOffset * 2))
        return path
    }
}

// MARK: - 1. Welcome

private struct WelcomeIllustration: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false
    @State private var bounce = 0

    private struct Ball {
        var y: CGFloat = 0
        var squash: CGFloat = 1
    }

    var body: some View {
        ZStack {
            PadelCourtShape()
                .trim(from: 0, to: drawn || reduceMotion ? 1 : 0)
                .stroke(Theme.Colors.accent.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 150, height: 270)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.4), value: drawn)

            HStack(spacing: 14) {
                ForEach(0..<2, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.Colors.accent)
                        .frame(width: 26, height: 120)
                        .rotationEffect(.degrees(20))
                        .scaleEffect(y: drawn || reduceMotion ? 1 : 0.01, anchor: .bottom)
                        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.65).delay(0.25 + Double(index) * 0.12), value: drawn)
                }
            }
            .shadow(color: Theme.Colors.accent.opacity(0.4), radius: 24)

            Circle()
                .fill(.white)
                .frame(width: 30, height: 30)
                .shadow(color: .white.opacity(0.4), radius: 10)
                .keyframeAnimator(initialValue: Ball(), trigger: bounce) { content, value in
                    content
                        .scaleEffect(x: 2 - value.squash, y: value.squash, anchor: .bottom)
                        .offset(y: value.y)
                } keyframes: { _ in
                    KeyframeTrack(\.y) {
                        LinearKeyframe(-260, duration: 0.01)
                        LinearKeyframe(-260, duration: 0.55)
                        CubicKeyframe(0, duration: 0.42)
                        CubicKeyframe(-80, duration: 0.3)
                        CubicKeyframe(0, duration: 0.3)
                        CubicKeyframe(-24, duration: 0.18)
                        CubicKeyframe(0, duration: 0.18)
                    }
                    KeyframeTrack(\.squash) {
                        LinearKeyframe(1, duration: 0.98)
                        LinearKeyframe(0.72, duration: 0.06)
                        SpringKeyframe(1, duration: 0.3)
                        LinearKeyframe(1, duration: 0.24)
                        LinearKeyframe(0.86, duration: 0.05)
                        SpringKeyframe(1, duration: 0.2)
                    }
                }
                .offset(x: 78, y: 78)
        }
        .onChange(of: isActive, initial: true) { _, active in
            guard active else { return }
            drawn = false
            withAnimation { drawn = true }
            if !reduceMotion { bounce += 1 }
        }
    }
}

// MARK: - 2. Rotation

private struct RotationIllustration: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// For each round, the slot (0–3) of players A–D. Slots 0,1 are one team (top),
    /// 2,3 the other (bottom): every player partners each other player once.
    private static let rounds: [[Int]] = [[0, 1, 2, 3], [0, 2, 1, 3], [0, 3, 2, 1]]
    private static let names = ["A", "B", "C", "D"]
    private static let tints: [UInt32] = [0xC7F36B, 0x8FD3FE, 0xFFB86B, 0xE6A7FF]

    var body: some View {
        if reduceMotion || !isActive {
            court(round: 0)
        } else {
            PhaseAnimator([0, 1, 2]) { round in
                court(round: round)
            } animation: { _ in
                .spring(response: 0.75, dampingFraction: 0.72).delay(1.1)
            }
        }
    }

    private func court(round: Int) -> some View {
        let width: CGFloat = 170, height: CGFloat = 270
        let slots = [
            CGPoint(x: width * 0.27, y: height * 0.22), CGPoint(x: width * 0.73, y: height * 0.22),
            CGPoint(x: width * 0.27, y: height * 0.78), CGPoint(x: width * 0.73, y: height * 0.78),
        ]
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: 0x1A2A20))
            PadelCourtShape()
                .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
            // Partner links for the current round.
            Path { path in
                path.move(to: slots[0]); path.addLine(to: slots[1])
                path.move(to: slots[2]); path.addLine(to: slots[3])
            }
            .stroke(Theme.Colors.accent.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [4, 5]))
            ForEach(0..<4, id: \.self) { player in
                let slot = Self.rounds[round][player]
                Text(Self.names[player])
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: 0x101210))
                    .frame(width: 44, height: 44)
                    .background(Color(hex: Self.tints[player]), in: Circle())
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                    .position(slots[slot])
            }
            Text("Round \(round + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(hex: 0x101210))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.Colors.accent, in: Capsule())
                .position(x: width / 2, y: height / 2)
                .contentTransition(.numericText())
        }
        .frame(width: width, height: height)
    }
}

// MARK: - 3. Watch

private struct WatchIllustration: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0

    /// Rally sequence: which side wins each point.
    private static let rallies: [Bool] = [true, true, false, true, false, true, true, false]

    private var score: (Int, Int) {
        var a = 12, b = 8
        for index in 0..<step { if Self.rallies[index % Self.rallies.count] { a += 1 } else { b += 1 } }
        return (a, b)
    }

    private var lastWinnerIsA: Bool {
        step == 0 ? true : Self.rallies[(step - 1) % Self.rallies.count]
    }

    var body: some View {
        ZStack {
            // Strap
            RoundedRectangle(cornerRadius: 30)
                .fill(Color(hex: 0x2A2D2A))
                .frame(width: 120, height: 300)
            // Case
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .fill(Color(hex: 0x3A3D3A))
                .frame(width: 200, height: 236)
                .overlay(
                    RoundedRectangle(cornerRadius: 46, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 2)
                )
            // Digital crown and action button
            Capsule().fill(Color(hex: 0xFF8A3D)).frame(width: 8, height: 34).offset(x: -103, y: 30)
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x4A4D4A)).frame(width: 12, height: 40).offset(x: 104, y: -24)
            // Screen
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.black)
                .frame(width: 176, height: 212)
            HStack(spacing: 6) {
                half(isA: true, value: score.0)
                half(isA: false, value: score.1)
            }
            .frame(width: 160, height: 150)
            .offset(y: 10)
            Text("Court 1")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: 0x101210))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.Colors.accent, in: Capsule())
                .offset(y: -82)
        }
        .task(id: isActive) {
            guard isActive, !reduceMotion else { return }
            step = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.1))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { step += 1 }
            }
        }
    }

    private func half(isA: Bool, value: Int) -> some View {
        let tapped = step > 0 && lastWinnerIsA == isA
        return ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(isA ? Theme.Colors.accent : Color(hex: 0x252925))
            // Tap ripple on the side that just scored.
            Circle()
                .stroke(isA ? Color.black.opacity(0.25) : Color.white.opacity(0.3), lineWidth: 2)
                .frame(width: 60, height: 60)
                .scaleEffect(tapped ? 1.6 : 0.4)
                .opacity(tapped ? 0 : 0.9)
                .animation(tapped ? .easeOut(duration: 0.7) : nil, value: step)
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(value: Double(value)))
                Text(isA ? "+1 A" : "+1 B")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(isA ? Color(hex: 0x101210) : .white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .scaleEffect(tapped ? 0.96 : 1)
    }
}

// MARK: - 4. Lock Screen

private struct LockScreenIllustration: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var points = 0

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1C2B22), Color(hex: 0x0E1410)], startPoint: .top, endPoint: .bottom))
                .frame(width: 236, height: 300)
                .overlay(
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 2)
                )
            VStack(spacing: 10) {
                dynamicIsland
                    .padding(.top, 14)
                Text("21:42")
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                lockScreenCard
            }
        }
        .frame(height: 300)
        .task(id: isActive) {
            guard isActive, !reduceMotion else { return }
            expanded = false
            points = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    expanded.toggle()
                    if expanded { points += 1 }
                }
            }
        }
    }

    private var dynamicIsland: some View {
        HStack {
            Text("\(15 + points)")
                .foregroundStyle(Theme.Colors.accent)
                .contentTransition(.numericText(value: Double(points)))
            if expanded {
                Spacer(minLength: 0)
                Text("Court 1")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
            Text("9").foregroundStyle(.white)
        }
        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
        .padding(.horizontal, 14)
        .frame(width: expanded ? 180 : 110, height: expanded ? 40 : 30)
        .background(.black, in: Capsule())
    }

    private var lockScreenCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Court 1 · Round 3")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Spacer()
            }
            HStack {
                Text("\(15 + points)")
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.Colors.accent)
                    .contentTransition(.numericText(value: Double(points)))
                Spacer()
                Text("–").foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("9")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 6) {
                Text("+1 A")
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(Theme.Colors.accent, in: Capsule())
                    .foregroundStyle(Color(hex: 0x101210))
                    .scaleEffect(expanded ? 0.94 : 1)
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 30, height: 24)
                    .background(Color.white.opacity(0.15), in: Capsule())
                Text("+1 B")
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(Color.white.opacity(0.15), in: Capsule())
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
        }
        .padding(12)
        .frame(width: 204)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - 5. Promises

private struct PromisesIllustration: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private let items: [(String, LocalizedStringKey)] = [
        ("wifi.slash", "Works offline"),
        ("person.crop.circle.badge.xmark", "No account needed"),
        ("lock.shield", "Data stays on your devices"),
        ("applewatch", "Apple Watch included"),
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: item.0)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(hex: 0x101210))
                        .frame(width: 44, height: 44)
                        .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(item.1)
                        .font(.padelName)
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.Colors.accent)
                        .opacity(shown ? 1 : 0)
                        .scaleEffect(shown || reduceMotion ? 1 : 0.3)
                        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.6).delay(0.25 + Double(index) * 0.12), value: shown)
                }
                .padding(Theme.Spacing.m)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .opacity(shown ? 1 : 0)
                .offset(x: shown || reduceMotion ? 0 : 30)
                .animation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.85).delay(Double(index) * 0.1), value: shown)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .onChange(of: isActive, initial: true) { _, active in
            guard active else { return }
            shown = false
            withAnimation { shown = true }
        }
    }
}
