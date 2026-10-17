import SwiftUI
import UIKit

// MARK: - Motion tokens
//
// Every animation in the iPhone app comes from here, so Reduce Motion is handled in one
// place: with it on, movement, scaling and bouncing collapse to short cross-fades.

enum Motion {
    /// Crisp response to a tap: buttons, toggles, score digits.
    static let snappy = Animation.snappy(duration: 0.28, extraBounce: 0.04)
    /// Physical, slightly bouncy arrival: cards, chips, badges.
    static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.72)
    /// Calm layout changes.
    static let smooth = Animation.spring(response: 0.55, dampingFraction: 0.9)
    /// Large hero movements: podium bars, dealing a round, the court unfolding.
    static let hero = Animation.spring(response: 0.8, dampingFraction: 0.78)
    /// What every animation becomes with Reduce Motion.
    static let fade = Animation.easeInOut(duration: 0.2)

    /// Delay for the n-th item of a staggered entrance, capped so long lists never wait.
    static func stagger(_ index: Int, step: Double = 0.06, cap: Double = 0.42) -> Double {
        min(Double(max(0, index)) * step, cap)
    }
}

extension Animation {
    /// This animation, or a short fade when Reduce Motion is on. For `withAnimation` in
    /// actions, where the environment value is not at hand.
    @MainActor
    var motionSafe: Animation {
        UIAccessibility.isReduceMotionEnabled ? Motion.fade : self
    }
}

// MARK: - Entrances

/// Fades and rises in once, after a stagger delay. A plain fade with Reduce Motion.
private struct StaggeredAppear: ViewModifier {
    let index: Int
    var distance: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0.01)
            .offset(y: shown || reduceMotion ? 0 : distance)
            .scaleEffect(shown || reduceMotion ? 1 : 0.98, anchor: .top)
            .onAppear {
                guard !shown else { return }
                withAnimation((reduceMotion ? Motion.fade : Motion.bouncy).delay(Motion.stagger(index))) {
                    shown = true
                }
            }
    }
}

/// A card "dealt" onto the table: drops in from above with a slight twist. Used when a
/// round's pairings appear. A fade with Reduce Motion.
private struct DealIn: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dealt = false

    func body(content: Content) -> some View {
        content
            .opacity(dealt ? 1 : 0.01)
            .rotationEffect(.degrees(dealt || reduceMotion ? 0 : (index.isMultiple(of: 2) ? -5 : 5)), anchor: .bottom)
            .offset(y: dealt || reduceMotion ? 0 : -46)
            .scaleEffect(dealt || reduceMotion ? 1 : 0.92)
            .onAppear {
                guard !dealt else { return }
                withAnimation((reduceMotion ? Motion.fade : Motion.bouncy).delay(0.05 + Motion.stagger(index, step: 0.09))) {
                    dealt = true
                }
            }
    }
}

/// Cards scale down and dim slightly as they scroll towards the edges.
private struct ScrollReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let reduce = reduceMotion
        return content.scrollTransition(.interactive, axis: .vertical) { view, phase in
            view
                .opacity(phase.isIdentity ? 1 : 0.5)
                .scaleEffect(phase.isIdentity || reduce ? 1 : 0.94)
        }
    }
}

extension View {
    /// Staggered fade-and-rise entrance (index 0 first).
    func staggeredAppear(_ index: Int, distance: CGFloat = 18) -> some View {
        modifier(StaggeredAppear(index: index, distance: distance))
    }

    /// Card-dealing entrance for new pairings.
    func dealIn(_ index: Int) -> some View {
        modifier(DealIn(index: index))
    }

    /// Scroll-linked scale and fade for cards in a scroll view.
    func scrollReveal() -> some View {
        modifier(ScrollReveal())
    }
}

// MARK: - Press feedback

/// Physical press for card-like buttons: a quick squeeze that springs back.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.75 : 1)
            .animation(reduceMotion ? Motion.fade : Motion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Live indicator

/// A lime dot with a ring that keeps expanding, for anything happening right now.
/// Static with Reduce Motion.
struct LiveDot: View {
    var color: Color = Theme.Colors.accent
    var size: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                if !reduceMotion {
                    Circle()
                        .fill(color.opacity(0.6))
                        .scaleEffect(pulsing ? 2.8 : 1)
                        .opacity(pulsing ? 0 : 0.9)
                        .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: pulsing)
                }
            }
            .onAppear { pulsing = true }
            .accessibilityHidden(true)
    }
}

// MARK: - Zoom transitions (iOS 18+)

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// Namespace shared by navigation sources and destinations for zoom transitions.
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Marks the view a zoom transition starts from (iOS 18+; no effect before).
    @ViewBuilder
    func zoomSource<ID: Hashable>(_ id: ID, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            if #available(iOS 18, *) {
                self.matchedTransitionSource(id: id, in: namespace)
            } else {
                self
            }
        } else {
            self
        }
    }

    /// Pushes this screen by zooming out of its source (iOS 18+; a normal push before).
    @ViewBuilder
    func zoomDestination<ID: Hashable>(_ id: ID, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            if #available(iOS 18, *) {
                self.navigationTransition(.zoom(sourceID: id, in: namespace))
            } else {
                self
            }
        } else {
            self
        }
    }
}
