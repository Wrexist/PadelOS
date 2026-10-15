import SwiftUI
import PadelCore

// MARK: - Buttons

/// The lime call to action: a lit gradient, a soft glow in dark mode and a springy press.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return configuration.label
            .font(.padelButton)
            .foregroundStyle(Theme.Colors.onAccent)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, Theme.Spacing.l)
            .background {
                shape.fill(LinearGradient(colors: [Theme.Colors.limeBright, Theme.Colors.accent, Theme.Colors.limeDeep], startPoint: .top, endPoint: .bottom))
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: 1))
            .shadow(color: (colorScheme == .dark ? Theme.Colors.accent.opacity(0.32) : Theme.Colors.ink.opacity(0.14)).opacity(isEnabled ? 1 : 0),
                    radius: configuration.isPressed ? 4 : 14, y: configuration.isPressed ? 2 : 6)
            .saturation(isEnabled ? 1 : 0.2)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return configuration.label
            .font(.padelButton)
            .foregroundStyle(role == .destructive ? Theme.Colors.danger : Theme.Colors.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Theme.Spacing.l)
            .background(Theme.Colors.surfaceRaised.opacity(configuration.isPressed ? 1 : 0.7), in: shape)
            .overlay(shape.strokeBorder(Theme.Colors.separator, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var padelPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var padelSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static var padelDestructive: SecondaryButtonStyle { SecondaryButtonStyle(role: .destructive) }
}

// MARK: - Surfaces

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.l

    func body(content: Content) -> some View {
        content.surfaceCard(padding: padding)
    }
}

extension View {
    func cardStyle(padding: CGFloat = Theme.Spacing.l) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

/// Small expanded caps above a group ("QUICK START"). Takes a localized key; use
/// `init(verbatim:)` for text that is already localized.
struct SectionHeader: View {
    private let title: Text
    private let trailing: String?

    init(_ title: LocalizedStringKey, trailing: String? = nil) {
        self.title = Text(title)
        self.trailing = trailing
    }

    init(verbatim title: String, trailing: String? = nil) {
        self.title = Text(verbatim: title)
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            title
                .font(.padelEyebrow)
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Spacing.s)
            if let trailing {
                Text(verbatim: trailing)
                    .font(.padelMeta.weight(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }
}

// MARK: - Players

struct PlayerAvatar: View {
    let name: String
    var size: CGFloat = 32
    /// Outline for a highlighted player (leader, winner).
    var ring: Color?

    var body: some View {
        let tint = AvatarPalette.color(for: name)
        Text(verbatim: Player(name: name).initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(tint)
                    .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .overlay(Circle().strokeBorder(ring ?? Color.white.opacity(0.12), lineWidth: ring == nil ? 1 : 2))
            .accessibilityHidden(true)
    }
}

struct PlayerChip: View {
    let name: String
    var detail: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            PlayerAvatar(name: name, size: 26)
            Text(verbatim: name)
                .font(.padelMeta.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            if let detail {
                Text(verbatim: detail)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.Colors.accentText)
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, 4)
        .padding(.trailing, Theme.Spacing.m)
        .background(Theme.Colors.surfaceRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Colors.separator.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Names of one side stacked vertically with avatars.
struct SideNamesView: View {
    let names: [String]
    var alignment: HorizontalAlignment = .leading
    var emphasized = false

    var body: some View {
        VStack(alignment: alignment, spacing: Theme.Spacing.xs) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                HStack(spacing: Theme.Spacing.s) {
                    if alignment == .leading { PlayerAvatar(name: name, size: 24) }
                    Text(verbatim: name)
                        .font(emphasized ? .padelName.weight(.bold) : .padelName)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if alignment == .trailing { PlayerAvatar(name: name, size: 24) }
                }
            }
        }
    }
}

// MARK: - Status

enum MatchBadgeKind {
    case live, upNext, finished, needsConfirmation

    var title: String {
        switch self {
        case .live: String(localized: "Live")
        case .upNext: String(localized: "Up next")
        case .finished: String(localized: "Finished")
        case .needsConfirmation: String(localized: "Confirm")
        }
    }

    var symbol: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .upNext: "clock"
        case .finished: "checkmark"
        case .needsConfirmation: "exclamationmark.circle"
        }
    }
}

struct StatusBadge: View {
    let kind: MatchBadgeKind

    var body: some View {
        HStack(spacing: 5) {
            if kind == .live {
                LiveDot(color: Theme.Colors.ink, size: 6)
            } else {
                Image(systemName: kind.symbol)
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            Text(verbatim: kind.title)
                .font(.padelEyebrow)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, 5)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var foreground: Color {
        switch kind {
        case .live, .needsConfirmation: Theme.Colors.onAccent
        case .upNext, .finished: Theme.Colors.textSecondary
        }
    }

    private var background: Color {
        switch kind {
        case .live: Theme.Colors.accent
        case .needsConfirmation: Theme.Colors.warning
        case .upNext, .finished: Theme.Colors.surfaceRaised
        }
    }
}

extension Match {
    func badge(rule: ScoringRule) -> MatchBadgeKind {
        if isCompleted { return .finished }
        if ScoringEngine.isAwaitingConfirmation(self, rule: rule) { return .needsConfirmation }
        if hasStarted { return .live }
        return .upNext
    }
}

/// A capsule that fills with lime and glows; springs to new values.
struct ProgressBar: View {
    let value: Double
    var height: CGFloat = 6
    var tint: Color = Theme.Colors.accent
    var track: Color = Theme.Colors.surfaceRaised

    var body: some View {
        let clamped = max(0, min(1, value))
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, clamped * proxy.size.width))
                    .shadow(color: tint.opacity(0.45), radius: 5)
                    .opacity(clamped > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(Motion.smooth, value: clamped)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}

// MARK: - Feedback

/// Empty state with a gently orbiting ring around a bouncing symbol.
struct EmptyStateView: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.Colors.accent.opacity(0.28), Theme.Colors.accent.opacity(0.04)], center: .center, startRadius: 4, endRadius: 46))
                    .frame(width: 84, height: 84)
                Circle()
                    .strokeBorder(Theme.Colors.accentText.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [2, 6]))
                    .frame(width: 112, height: 112)
                    .rotationEffect(.degrees(appeared && !reduceMotion ? 360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration: 30).repeatForever(autoreverses: false), value: appeared)
                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accentText)
                    .symbolEffect(.bounce, value: appeared)
            }
            .padding(.bottom, Theme.Spacing.xs)
            .accessibilityHidden(true)
            Text(title)
                .font(.padelSection)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.padelMeta)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .accessibilityElement(children: .combine)
        .onAppear { appeared = true }
    }
}

struct MessageBanner: View {
    enum Style { case error, warning, info }

    let style: Style
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(verbatim: message)
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(verbatim: actionTitle)
                    }
                    .font(.padelMeta.weight(.bold))
                    .foregroundStyle(Theme.Colors.accentText)
                }
            }
            .padding(.top, 5)
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                }
                .accessibilityLabel("Dismiss")
                .padding(.top, -Theme.Spacing.s)
                .padding(.trailing, -Theme.Spacing.m)
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var symbol: String {
        switch style {
        case .error: "exclamationmark.triangle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch style {
        case .error: Theme.Colors.danger
        case .warning: Theme.Colors.warning
        case .info: Theme.Colors.accentText
        }
    }
}

/// Transient confirmation with an optional undo action, floating on glass.
struct ToastView: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.accentText)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(.padelMeta.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(verbatim: actionTitle)
                }
                .font(.padelMeta.weight(.heavy))
                .foregroundStyle(Theme.Colors.accentText)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .glassSurface(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// Small key-value row used in forms and summaries.
struct ValueRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.Colors.accentText)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(verbatim: value)
                .foregroundStyle(Theme.Colors.textSecondary)
                .contentTransition(.numericText())
        }
        .font(.padelName)
        .accessibilityElement(children: .combine)
    }
}
