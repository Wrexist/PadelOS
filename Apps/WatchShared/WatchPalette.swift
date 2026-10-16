import SwiftUI

/// "Night Court" palette for the watch app and its complication: near-black court,
/// lime energy, a white ball. Kept here (not in `Apps/Shared`) because the complication
/// extension does not compile the iPhone design system; the values match `Theme`.
enum WatchPalette {
    /// Near-black court surface.
    static let ink = rgb(0x101210)
    /// Slightly lifted surface for cards.
    static let surface = rgb(0x1A1D1A)
    /// Raised controls on top of cards.
    static let raised = rgb(0x252925)
    /// Deep green of the playing surface, used for the court halves.
    static let turf = rgb(0x0F1A13)
    /// Court Lime: Team A, live state, primary actions.
    static let lime = rgb(0xC7F36B)
    /// Text and icons on a lime fill.
    static let onLime = rgb(0x101210)
    /// Team B and the ball.
    static let chalk = Color.white
    /// Secondary text.
    static let muted = rgb(0x8B928A)
    /// Court markings.
    static let line = Color.white.opacity(0.16)
    /// Golden point, first place.
    static let gold = rgb(0xF5C451)
    static let silver = rgb(0xC9D1D9)
    static let bronze = rgb(0xD69B6B)
    /// Pending sync, warnings.
    static let amber = rgb(0xF5C451)

    static func rgb(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Font {
    /// Tall scoreboard numerals: heavy, compressed, tabular.
    static func watchScore(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        Font.system(size: size, weight: weight).width(.compressed).monospacedDigit()
    }

    /// Condensed uppercase labels ("COURT 1", team names).
    static func watchLabel(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        Font.system(style, weight: weight).width(.condensed)
    }
}
