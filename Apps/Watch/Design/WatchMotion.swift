import SwiftUI
import PadelStore

// MARK: - Motion tokens
//
// Physical springs for everything that moves. Views ask `WatchMotion.resolve` so Reduce
// Motion turns movement into short cross-fades instead.

enum WatchMotion {
    /// A point lands: fast, a little bounce.
    static let pop = Animation.spring(response: 0.3, dampingFraction: 0.58)
    /// Layout settling after a change (banners, bars, cards).
    static let settle = Animation.spring(response: 0.5, dampingFraction: 0.8)
    /// Quick UI feedback.
    static let snappy = Animation.snappy(duration: 0.22)
    /// Ball crossing the net.
    static let flight = Animation.spring(response: 0.46, dampingFraction: 0.72)
    /// Replacement for movement under Reduce Motion.
    static let fade = Animation.easeInOut(duration: 0.18)

    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }
}

// MARK: - Buttons

/// Presses sink slightly and spring back.
struct WatchPressableStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(WatchMotion.snappy, value: configuration.isPressed)
    }
}

// MARK: - Live dot

/// Lime dot with a breathing halo: "this match is being played right now".
struct WatchLiveDot: View {
    var color: Color = WatchPalette.lime
    var size: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                if !reduceMotion && !isLuminanceReduced {
                    Circle()
                        .fill(color)
                        .phaseAnimator([false, true]) { content, expanded in
                            content
                                .scaleEffect(expanded ? 2.8 : 1)
                                .opacity(expanded ? 0 : 0.55)
                        } animation: { expanded in
                            expanded ? .easeOut(duration: 1.2) : .easeIn(duration: 0.25)
                        }
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Sync chip

/// Compact sync state: a check when everything is on the iPhone, an amber count of
/// points still on the watch that drains (and morphs back into the check) as they sync.
struct WatchSyncChip: View {
    let status: WatchStore.SyncStatus

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: isSending)
            if case .pending(let count, _) = status {
                Text(verbatim: "\(count)")
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
        .font(.system(size: 12, weight: .heavy).monospacedDigit())
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.16), in: Capsule())
        .animation(WatchMotion.pop, value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var isSending: Bool {
        if case .pending(_, let reachable) = status { return reachable }
        return false
    }

    private var symbol: String {
        switch status {
        case .waitingForPhone: "iphone.slash"
        case .upToDate: "checkmark"
        case .pending(_, let reachable): reachable ? "arrow.triangle.2.circlepath" : "arrow.up"
        }
    }

    private var tint: Color {
        switch status {
        case .upToDate: WatchPalette.lime
        case .waitingForPhone: WatchPalette.muted
        case .pending: WatchPalette.amber
        }
    }

    private var label: String {
        switch status {
        case .waitingForPhone: String(localized: "Not synced yet")
        case .upToDate: String(localized: "Saved on iPhone")
        case .pending(let count, _): String(localized: "\(count) changes waiting to sync")
        }
    }
}

/// Amber count of points still on the watch, as a badge; hidden when all is synced.
struct WatchSyncBadge: View {
    let status: WatchStore.SyncStatus

    var body: some View {
        Group {
            if case .pending(let count, _) = status {
                Text(verbatim: "\(count)")
                    .font(.system(size: 10, weight: .heavy).monospacedDigit())
                    .foregroundStyle(WatchPalette.ink)
                    .contentTransition(.numericText(value: Double(count)))
                    .padding(.horizontal, 5)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(WatchPalette.amber, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(String(localized: "\(count) changes waiting to sync"))
            }
        }
        .animation(WatchMotion.pop, value: status)
    }
}

// MARK: - Ball

/// The white ball: a lit sphere with a seam and a faint lime glow.
struct WatchBall: View {
    var size: CGFloat = 14
    var glows = true

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [.white, Color(white: 0.78)],
                    center: UnitPoint(x: 0.35, y: 0.3),
                    startRadius: 0,
                    endRadius: size * 0.75
                ))
            WatchBallSeam()
                .stroke(WatchPalette.ink.opacity(0.35), style: StrokeStyle(lineWidth: max(1, size / 12), lineCap: .round))
        }
        .frame(width: size, height: size)
        .shadow(color: glows ? WatchPalette.lime.opacity(0.7) : .clear, radius: size * 0.45)
        .accessibilityHidden(true)
    }
}

// MARK: - Confetti

/// A one-shot burst of lime, white and gold confetti that falls with gravity and fades.
struct WatchConfetti: View {
    var count = 42
    var duration: Double = 2.8
    /// Where the burst starts, as a fraction of the view.
    var origin = UnitPoint(x: 0.5, y: 0.4)
    @State private var start = Date()
    @State private var finished = false

    private static let colors: [Color] = [WatchPalette.lime, .white, WatchPalette.gold, WatchPalette.lime.opacity(0.7)]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: finished)) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard t < duration else { return }
                let x0 = size.width * origin.x
                let y0 = size.height * origin.y
                let fadeStart = duration * 0.55
                let opacity = t < fadeStart ? 1 : max(0, 1 - (t - fadeStart) / (duration - fadeStart))
                for index in 0..<count {
                    let angle = -Double.pi * (0.08 + 0.84 * Self.unit(index, 1))
                    let speed = 70 + 120 * Self.unit(index, 2)
                    let x = x0 + cos(angle) * speed * t
                    let y = y0 + sin(angle) * speed * t + 0.5 * 260 * t * t
                    let spin = (Self.unit(index, 3) - 0.5) * 14 * t
                    var piece = context
                    piece.opacity = opacity
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(spin))
                    let isDisc = index % 5 == 0
                    let rect = isDisc ? CGRect(x: -2.5, y: -2.5, width: 5, height: 5) : CGRect(x: -2, y: -4, width: 4, height: 8)
                    let shape = isDisc ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1)
                    piece.fill(shape, with: .color(Self.colors[index % Self.colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(duration))
            finished = true
        }
    }

    /// Deterministic pseudo-random value in 0..<1 per piece.
    private static func unit(_ index: Int, _ salt: Int) -> Double {
        let value = sin(Double(index) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return value - value.rounded(.down)
    }
}

// MARK: - Labels

/// Uppercase condensed overline, e.g. "COURT 1".
struct WatchOverline: View {
    let text: String
    var color: Color = WatchPalette.muted

    var body: some View {
        Text(text)
            .font(.watchLabel(.caption2, weight: .heavy))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
