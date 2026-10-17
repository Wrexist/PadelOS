import SwiftUI

/// A burst of lime-and-white confetti, fired each time `trigger` changes. Drawn in one
/// Canvas and only animated for the 2.6 s it is visible. With Reduce Motion it becomes a
/// soft lime flash.
struct ConfettiBurst: View {
    let trigger: Int
    /// Where the burst starts, relative to the view.
    var origin: UnitPoint = UnitPoint(x: 0.5, y: 0.35)
    var count: Int = 110
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst: Burst?

    fileprivate struct Particle {
        var angle: Double
        var speed: Double
        var spin: Double
        var flutter: Double
        var width: Double
        var height: Double
        var color: Color
        var isCircle: Bool
    }

    fileprivate struct Burst {
        let id = UUID()
        let start = Date()
        var particles: [Particle]
    }

    private static let duration: TimeInterval = 2.6
    private static let palette: [Color] = [
        Theme.Colors.accent, Theme.Colors.limeBright, Theme.Colors.limeDeep, .white, Color(hex: 0xEAFBC4),
    ]

    var body: some View {
        ZStack {
            if let burst {
                if reduceMotion {
                    RadialGradient(colors: [Theme.Colors.accent.opacity(0.35), .clear], center: origin, startRadius: 0, endRadius: 360)
                        .transition(.opacity)
                } else {
                    TimelineView(.animation) { context in
                        let elapsed = context.date.timeIntervalSince(burst.start)
                        Canvas { graphics, size in
                            draw(burst.particles, elapsed: elapsed, in: &graphics, size: size)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        let particles = (0..<count).map { _ in
            Particle(
                angle: Double.random(in: (-Double.pi * 0.92)...(-Double.pi * 0.08)),
                speed: Double.random(in: 520...1150),
                spin: Double.random(in: -9...9),
                flutter: Double.random(in: 4...11),
                width: Double.random(in: 6...11),
                height: Double.random(in: 9...16),
                color: Self.palette.randomElement() ?? Theme.Colors.accent,
                isCircle: Double.random(in: 0...1) < 0.22
            )
        }
        let next = Burst(particles: particles)
        withAnimation(Motion.fade) { burst = next }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.duration))
            if burst?.id == next.id {
                withAnimation(Motion.fade) { burst = nil }
            }
        }
    }

    private func draw(_ particles: [Particle], elapsed: TimeInterval, in graphics: inout GraphicsContext, size: CGSize) {
        let gravity = 1500.0
        let start = CGPoint(x: size.width * origin.x, y: size.height * origin.y)
        let fadeStart = Self.duration - 0.8
        let alpha = elapsed < fadeStart ? 1 : max(0, 1 - (elapsed - fadeStart) / 0.8)
        // Air drag: particles slow down, then mostly fall.
        let dragged = (1 - exp(-elapsed * 2.2)) / 2.2
        for particle in particles {
            let x = start.x + cos(particle.angle) * particle.speed * dragged + sin(elapsed * particle.flutter) * 10
            let y = start.y + sin(particle.angle) * particle.speed * dragged + 0.5 * gravity * elapsed * elapsed * 0.35
            var context = graphics
            context.opacity = alpha
            context.translateBy(x: x, y: y)
            context.rotate(by: .radians(particle.spin * elapsed))
            // Flip around one axis so the paper seems to tumble.
            context.scaleBy(x: cos(elapsed * particle.flutter), y: 1)
            let rect = CGRect(x: -particle.width / 2, y: -particle.height / 2, width: particle.width, height: particle.height)
            let shape = particle.isCircle ? Path(ellipseIn: rect.insetBy(dx: 0, dy: (particle.height - particle.width) / 2)) : Path(roundedRect: rect, cornerRadius: 2)
            context.fill(shape, with: .color(particle.color))
        }
    }
}

/// Expanding rings from a point: the "pop" when a point is scored.
struct ScoreRipple: View {
    let color: Color
    @State private var expanded = false

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 3)
            .frame(width: 80, height: 80)
            .scaleEffect(expanded ? 3.2 : 0.3)
            .opacity(expanded ? 0 : 0.9)
            .onAppear {
                withAnimation(.easeOut(duration: 0.65)) { expanded = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
