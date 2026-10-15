import SwiftUI

/// "Night Court": the app's living background. A slow aurora of lime light (a mesh
/// gradient on iOS 18, radial glows before), faint court lines that fade out down the
/// screen, and a light sweep that runs across the lines every few seconds, like
/// floodlights. With Reduce Motion it is a still frame.
struct NightCourtBackground: View {
    enum Style {
        /// Animated: Home, the tournament, onboarding.
        case living
        /// Same look, no animation: forms, sheets, secondary screens.
        case still
    }

    var style: Style = .living
    /// Strength of the lime glow (onboarding uses more).
    var glow: Double = 1
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isAnimated: Bool { style == .living && !reduceMotion }

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            Theme.Colors.background
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimated)) { context in
                let time = isAnimated ? context.date.timeIntervalSinceReferenceDate : 0
                ZStack {
                    Aurora(time: time, glow: glow, dark: dark)
                    if isAnimated {
                        FloodlightSweep(time: time, dark: dark)
                    }
                }
            }
            CourtLines()
                .stroke(dark ? Color.white.opacity(0.045) : Theme.Colors.ink.opacity(0.05), lineWidth: 1)
                .mask {
                    LinearGradient(colors: [.white, .white.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Slowly drifting lime light.
private struct Aurora: View {
    let time: Double
    let glow: Double
    let dark: Bool

    var body: some View {
        if #available(iOS 18, *) {
            MeshGradient(width: 3, height: 3, points: points, colors: colors, smoothsColors: true)
        } else {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    RadialGradient(colors: [glowColor, .clear], center: .center, startRadius: 0, endRadius: size.width * 0.9)
                        .frame(width: size.width * 1.8, height: size.width * 1.8)
                        .position(x: size.width * (0.15 + 0.1 * sin(time * 0.3)), y: size.height * 0.05)
                    RadialGradient(colors: [secondColor, .clear], center: .center, startRadius: 0, endRadius: size.width * 0.8)
                        .frame(width: size.width * 1.6, height: size.width * 1.6)
                        .position(x: size.width * (0.95 + 0.08 * cos(time * 0.23)), y: size.height * 0.55)
                }
            }
        }
    }

    private var base: Color { Theme.Colors.background }

    /// Lime-tinted light; stronger on hero screens.
    private var glowColor: Color {
        dark ? Color(hex: 0x2C3D12).opacity(min(1, 0.75 * glow)) : Color(hex: 0xE2F6B0).opacity(min(1, 0.9 * glow))
    }

    private var secondColor: Color {
        dark ? Color(hex: 0x10261F).opacity(0.8) : Color(hex: 0xE4EFE6)
    }

    @available(iOS 18, *)
    private var colors: [Color] {
        let bg = dark ? Color(hex: 0x101210) : Color(hex: 0xF3F4EF)
        let lime = dark ? (glow > 1 ? Color(hex: 0x34491A) : Color(hex: 0x26331A)) : Color(hex: 0xE5F6B8)
        let teal = dark ? Color(hex: 0x0F201B) : Color(hex: 0xE6F0E8)
        return [
            lime, lime.mix(with: bg, by: 0.45), bg,
            lime.mix(with: bg, by: 0.6), bg, teal,
            bg, bg, bg,
        ]
    }

    @available(iOS 18, *)
    private var points: [SIMD2<Float>] {
        let s = Float(sin(time * 0.31))
        let c = Float(cos(time * 0.23))
        let top = SIMD2<Float>(0.5 + 0.12 * s, 0)
        let left = SIMD2<Float>(0, 0.35 + 0.08 * c)
        let center = SIMD2<Float>(0.45 + 0.12 * c, 0.4 + 0.08 * s)
        let right = SIMD2<Float>(1, 0.45 - 0.1 * s)
        let bottom = SIMD2<Float>(0.5 - 0.1 * c, 1)
        return [
            SIMD2<Float>(0, 0), top, SIMD2<Float>(1, 0),
            left, center, right,
            SIMD2<Float>(0, 1), bottom, SIMD2<Float>(1, 1),
        ]
    }
}

/// A band of light crossing the court lines diagonally every nine seconds.
private struct FloodlightSweep: View {
    let time: Double
    let dark: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let cycle = (time / 9).truncatingRemainder(dividingBy: 1)
            // Travels during the first 55 % of the cycle, then rests off screen.
            let progress = min(1, cycle / 0.55)
            CourtLines()
                .stroke(Theme.Colors.accent.opacity(dark ? 0.35 : 0.55), lineWidth: 1.2)
                .mask {
                    LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: width * 0.55, height: proxy.size.height * 1.6)
                        .rotationEffect(.degrees(18))
                        .offset(x: -width * 0.8 + progress * width * 2.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .mask {
                    LinearGradient(colors: [.white, .white.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom)
                }
        }
    }
}

/// Court-line grid: wide vertical lanes with a padel court's service lines at the top.
struct CourtLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lane = max(60, rect.width / 6)
        var x = rect.minX + lane / 2
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += lane
        }
        // A court outline near the top: baseline, service line, net.
        let courtTop = rect.minY + rect.height * 0.08
        for fraction in [0.0, 0.14, 0.32] {
            let y = courtTop + rect.height * fraction
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

extension View {
    /// Standard screen background (the Night Court, still by default).
    func screenBackground(_ style: NightCourtBackground.Style = .still) -> some View {
        background { NightCourtBackground(style: style) }
    }
}
