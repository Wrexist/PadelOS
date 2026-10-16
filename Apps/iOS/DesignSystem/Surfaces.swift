import SwiftUI

// MARK: - iPhone-only tokens
//
// Additions to the shared `Theme` (Apps/Shared) used only by the iPhone app. The shared
// token names stay untouched because the watch app uses them too.

extension Theme.Colors {
    /// The near-black of the icon. Scoreboards and the scoring court use it in both modes.
    static let ink = Color(hex: 0x101210)
    /// Graphite of the Team B half of the court and of always-dark scoreboard cards.
    static let graphite = Color(hex: 0x1B1F1B)
    static let graphiteRaised = Color(hex: 0x272C27)
    /// Brighter and deeper lime for gradients on lime fills.
    static let limeBright = Color(hex: 0xD9FA8C)
    static let limeDeep = Color(hex: 0xA9DB45)
    /// Grey text on always-dark surfaces (≥ 4.5:1 on graphite).
    static let onDarkSecondary = Color(hex: 0x9AA198)
}

extension Theme.Radius {
    /// Cards and tiles.
    static let card: CGFloat = 24
    /// Hero cards and the scoring court.
    static let hero: CGFloat = 32
}

// MARK: - Typography

extension Font {
    /// Wide, heavy display type for hero headlines.
    static let padelDisplay = Font.system(.largeTitle, design: .default, weight: .black).width(.expanded)
    /// Screen and card headlines.
    static let padelHeadline = Font.system(.title2, design: .default, weight: .heavy).width(.expanded)
    /// Small expanded caps for eyebrows and section labels ("NOW PLAYING").
    static let padelEyebrow = Font.system(.caption, design: .default, weight: .bold).width(.expanded)

    /// Scoreboard numerals: heavy, condensed, tabular. Size comes from the layout.
    static func padelScoreboard(size: CGFloat) -> Font {
        Font.system(size: size, weight: .black, design: .default).width(.condensed).monospacedDigit()
    }
}

// MARK: - Surfaces

/// Solid card with a hairline highlight on its top edge. Cheap to draw, so it is used for
/// everything in lists; glass is reserved for floating chrome.
struct SurfaceCard: ViewModifier {
    var padding: CGFloat = Theme.Spacing.l
    var cornerRadius: CGFloat = Theme.Radius.card
    /// Lime outline for something live or selected.
    var highlight: Color?
    var fill: Color = Theme.Colors.surface
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.10 : 0.9), Color.white.opacity(colorScheme == .dark ? 0.02 : 0.3)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
            .overlay {
                if let highlight {
                    shape.strokeBorder(highlight, lineWidth: 1.5)
                }
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 14, y: 6)
    }
}

extension View {
    func surfaceCard(padding: CGFloat = Theme.Spacing.l, cornerRadius: CGFloat = Theme.Radius.card, highlight: Color? = nil, fill: Color = Theme.Colors.surface) -> some View {
        modifier(SurfaceCard(padding: padding, cornerRadius: cornerRadius, highlight: highlight, fill: fill))
    }

    /// Floating chrome (bottom bars, toasts, small round buttons): Liquid Glass on iOS 26,
    /// a thin material before.
    @ViewBuilder
    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background {
                    if let tint { shape.fill(tint.opacity(0.25)) }
                }
                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
    }

    @available(iOS 26, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Round 44 pt glass button for toolbars and headers.
struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
            .glassSurface(Circle(), interactive: true)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassIconButtonStyle {
    static var glassIcon: GlassIconButtonStyle { GlassIconButtonStyle() }
}

/// Background of a bottom action bar: the screen colour fading in over the content, so
/// list rows never show through the buttons.
struct BottomBarFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.Colors.background.opacity(0), location: 0),
                .init(color: Theme.Colors.background.opacity(0.97), location: 0.1),
                .init(color: Theme.Colors.background, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
