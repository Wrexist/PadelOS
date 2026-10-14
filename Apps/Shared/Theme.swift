import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Color tokens
//
// Semantic tokens only; views never use raw hex values. The watch is always dark, the
// iPhone adapts. Accent fills keep the Court Lime in both modes, but lime is too light for
// text on a light background, so tinted text uses a darker olive in light mode.

enum Theme {
    enum Colors {
        static let background = Color.dynamic(light: 0xF3F4EF, dark: 0x101210)
        static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x1A1D1A)
        static let surfaceRaised = Color.dynamic(light: 0xE9EBE4, dark: 0x252925)
        static let textPrimary = Color.dynamic(light: 0x101210, dark: 0xFFFFFF)
        static let textSecondary = Color.dynamic(light: 0x5B6259, dark: 0x8B928A)
        static let separator = Color.dynamic(light: 0xDADDD4, dark: 0x2C302C)
        /// Court Lime, used for fills (buttons, progress, badges).
        static let accent = Color(hex: 0xC7F36B)
        /// Text and icons placed on an accent fill.
        static let onAccent = Color(hex: 0x101210)
        /// Accent-coloured text/icons on the background.
        static let accentText = Color.dynamic(light: 0x4B6A0F, dark: 0xC7F36B)
        static let danger = Color.dynamic(light: 0xC0392B, dark: 0xFF6B5E)
        static let warning = Color.dynamic(light: 0x8A5A00, dark: 0xF5C451)
        static let success = Color.dynamic(light: 0x2E7D32, dark: 0x8BE38F)
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 14
        static let large: CGFloat = 20
    }

    /// Minimum interactive size from the Human Interface Guidelines.
    static let minimumTapTarget: CGFloat = 44
}

// MARK: - Typography

extension Font {
    /// Screen titles.
    static let padelTitle = Font.system(.title, design: .default).weight(.bold)
    /// Large hero headline (Home).
    static let padelHero = Font.system(.largeTitle, design: .default).weight(.heavy)
    /// Section headings inside screens.
    static let padelSection = Font.system(.headline, design: .default).weight(.semibold)
    /// Uppercase overline labels ("PLAYERS", "COURT 1").
    static let padelOverline = Font.system(.caption, design: .default).weight(.semibold)
    /// Player names in match cards.
    static let padelName = Font.system(.body, design: .default).weight(.medium)
    /// Secondary metadata.
    static let padelMeta = Font.system(.footnote, design: .default)
    /// Buttons.
    static let padelButton = Font.system(.body, design: .default).weight(.semibold)

    /// Match score digits. Use with `@ScaledMetric` sizes so Dynamic Type scales them.
    static func padelScore(size: CGFloat) -> Font {
        Font.system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #else
        Color(hex: dark)
        #endif
    }
}

#if os(iOS)
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

/// Stable avatar tint derived from a name (independent of process hashing seeds).
enum AvatarPalette {
    static let tints: [UInt32] = [0x3B4A2F, 0x2F3F4A, 0x4A3B2F, 0x41304A, 0x2F4A44, 0x4A2F38, 0x3F4A2F, 0x2F354A]

    static func color(for name: String) -> Color {
        var value: UInt32 = 5381
        for scalar in name.lowercased().unicodeScalars {
            value = (value &* 33) &+ scalar.value
        }
        return Color(hex: tints[Int(value % UInt32(tints.count))])
    }
}
