import SwiftUI
import PadelCore

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.padelButton)
            .foregroundStyle(Theme.Colors.onAccent)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, Theme.Spacing.l)
            .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.padelButton)
            .foregroundStyle(role == .destructive ? Theme.Colors.danger : Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Theme.Spacing.l)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(Theme.Colors.separator, lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
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
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
    }
}

extension View {
    func cardStyle(padding: CGFloat = Theme.Spacing.l) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Standard screen background.
    func screenBackground() -> some View {
        background(Theme.Colors.background.ignoresSafeArea())
    }
}

struct SectionHeader: View {
    let title: Text
    var trailing: String?

    init(title: LocalizedStringKey, trailing: String? = nil) {
        self.title = Text(title)
        self.trailing = trailing
    }

    /// For text that is already localized.
    @_disfavoredOverload
    init(title: String, trailing: String? = nil) {
        self.title = Text(verbatim: title)
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            title
                .textCase(.uppercase)
                .font(.padelOverline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.padelMeta)
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

    var body: some View {
        Text(Player(name: name).initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(AvatarPalette.color(for: name), in: Circle())
            .accessibilityHidden(true)
    }
}

struct PlayerChip: View {
    let name: String
    var detail: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            PlayerAvatar(name: name, size: 24)
            Text(name)
                .font(.padelMeta.weight(.medium))
                .foregroundStyle(Theme.Colors.textPrimary)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.leading, Theme.Spacing.xs)
        .padding(.trailing, Theme.Spacing.m)
        .background(Theme.Colors.surfaceRaised, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Names of one side stacked vertically with avatars.
struct SideNamesView: View {
    let names: [String]
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: Theme.Spacing.xs) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                HStack(spacing: Theme.Spacing.s) {
                    if alignment == .leading { PlayerAvatar(name: name, size: 24) }
                    Text(name)
                        .font(.padelName)
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
        Label(kind.title, systemImage: kind.symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
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

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.surfaceRaised)
                Capsule().fill(Theme.Colors.accent)
                    .frame(width: max(0, min(1, value)) * proxy.size.width)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

// MARK: - Feedback

struct EmptyStateView: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.Colors.accentText)
                .accessibilityHidden(true)
            Text(title)
                .font(.padelSection)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(message)
                .font(.padelMeta)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .accessibilityElement(children: .combine)
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
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(message)
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.padelMeta.weight(.semibold))
                        .foregroundStyle(Theme.Colors.accentText)
                }
            }
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                }
                .accessibilityLabel("Dismiss")
                .padding(.top, -Theme.Spacing.m)
                .padding(.trailing, -Theme.Spacing.m)
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(tint.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
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

/// Transient confirmation with an optional undo action.
struct ToastView: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(message)
                .font(.padelMeta.weight(.medium))
                .foregroundStyle(Theme.Colors.textPrimary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.padelMeta.weight(.bold))
                    .foregroundStyle(Theme.Colors.accentText)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .background(Theme.Colors.surfaceRaised, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
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
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .font(.padelName)
        .accessibilityElement(children: .combine)
    }
}
