import SwiftUI

/// "Night Court" tokens for the Live Activity. The extension does not compile the app's
/// design system, so the few values it needs live here (same values as `Theme`).
enum LiveStyle {
    static let ink = rgb(0x101210)
    static let surface = rgb(0x1A1D1A)
    static let raised = rgb(0x2A2F2A)
    static let lime = rgb(0xC7F36B)
    static let chalk = Color.white
    static let muted = rgb(0x8B928A)
    static let gold = rgb(0xF5C451)
    static let amber = rgb(0xF5C451)

    static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Tall scoreboard numerals: heavy, compressed, tabular.
    static func score(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.compressed).monospacedDigit()
    }

    /// Condensed uppercase labels.
    static func label(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, weight: weight).width(.condensed)
    }
}

/// A white ball with a seam, the PadelOS mark.
struct LiveBall: View {
    var size: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [.white, Color(white: 0.8)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.75))
            LiveBallSeam()
                .stroke(LiveStyle.ink.opacity(0.35), style: StrokeStyle(lineWidth: max(0.8, size / 12), lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct LiveBallSeam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: rect.minX + w * 0.16, y: rect.minY + h * 0.14))
        path.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.16, y: rect.minY + h * 0.86), control: CGPoint(x: rect.minX + w * 0.52, y: rect.midY))
        path.move(to: CGPoint(x: rect.minX + w * 0.84, y: rect.minY + h * 0.14))
        path.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.84, y: rect.minY + h * 0.86), control: CGPoint(x: rect.minX + w * 0.48, y: rect.midY))
        return path
    }
}

/// Lime rail with the ball at its head: how far through the match we are.
struct LiveRail: View {
    let progress: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let fill = max(height + 4, proxy.size.width * min(1, max(0, progress)))
            ZStack(alignment: .leading) {
                Capsule().fill(LiveStyle.chalk.opacity(0.14))
                    .frame(height: height)
                Capsule()
                    .fill(LinearGradient(colors: [LiveStyle.lime.opacity(0.55), LiveStyle.lime], startPoint: .leading, endPoint: .trailing))
                    .frame(width: fill, height: height)
                LiveBall(size: height + 6)
                    .offset(x: fill - height - 6)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: height + 6)
        .accessibilityHidden(true)
    }
}
