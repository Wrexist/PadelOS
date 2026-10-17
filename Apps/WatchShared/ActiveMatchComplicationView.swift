import SwiftUI
import WidgetKit

/// The complication's faces, shared by the widget extension and the watch app (which
/// renders them in its screenshot gallery). The family is passed in rather than read
/// from the environment so the app can draw every family side by side.
struct ActiveMatchComplicationView: View {
    let family: WidgetFamily
    let snapshot: ActiveMatchSnapshot?

    var body: some View {
        if let snapshot {
            match(snapshot)
        } else {
            empty
        }
    }

    @ViewBuilder
    private func match(_ match: ActiveMatchSnapshot) -> some View {
        switch family {
        case .accessoryRectangular:
            ComplicationRectangular(match: match)
        case .accessoryCircular:
            ComplicationCircular(match: match)
        case .accessoryCorner:
            ComplicationCorner(match: match)
        default:
            Text("Court \(match.court) \(match.scoreA)–\(match.scoreB)")
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var empty: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 8) {
                ComplicationBall(size: 22)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text("PadelOS")
                        .font(.watchLabel(.headline, weight: .heavy))
                        .widgetAccentable()
                    Text("No active match")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Text("PadelOS")
        case .accessoryCorner:
            ComplicationBall(size: 20)
                .widgetAccentable()
                .widgetLabel("PadelOS")
        default:
            ZStack {
                AccessoryWidgetBackground()
                ComplicationBall(size: 24)
                    .widgetAccentable()
            }
        }
    }
}

/// Header with a live dot, two team rows with scoreboard numerals and a thin progress
/// rail along the bottom.
private struct ComplicationRectangular: View {
    let match: ActiveMatchSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle()
                    .fill(match.isFinished ? WatchPalette.muted : WatchPalette.lime)
                    .frame(width: 6, height: 6)
                Text("Court \(match.court)")
                    .textCase(.uppercase)
                Spacer(minLength: 2)
                Text(match.isFinished ? String(localized: "Final") : (match.situation ?? match.roundLabel))
                    .textCase(.uppercase)
                    .lineLimit(1)
            }
            .font(.watchLabel(.caption2, weight: .heavy))
            .foregroundStyle(WatchPalette.lime)
            .widgetAccentable()

            row(match.teamA, match.scoreA, leads: match.scoreA > match.scoreB)
            row(match.teamB, match.scoreB, leads: match.scoreB > match.scoreA)

            if let progress = match.gaugeProgress {
                ComplicationRail(progress: progress)
                    .padding(.top, 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(String(localized: "Court \(match.court)")). \(match.teamA) \(match.scoreA), \(match.teamB) \(match.scoreB)."))
    }

    private func row(_ name: String, _ score: Int, leads: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(name)
                .font(.watchLabel(.footnote, weight: leads ? .bold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Text(verbatim: "\(score)")
                .font(.watchScore(20))
                .contentTransition(.numericText(value: Double(score)))
        }
        .foregroundStyle(leads ? WatchPalette.chalk : WatchPalette.chalk.opacity(0.75))
    }
}

/// Lime capacity ring around "C1" and the score.
private struct ComplicationCircular: View {
    let match: ActiveMatchSnapshot

    var body: some View {
        if let progress = match.gaugeProgress {
            Gauge(value: progress) {
                Text("C\(match.court)")
            } currentValueLabel: {
                center
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(WatchPalette.lime)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                center
            }
        }
    }

    private var center: some View {
        VStack(spacing: -2) {
            Text("C\(match.court)")
                .font(.watchLabel(.caption2, weight: .heavy))
                .foregroundStyle(WatchPalette.lime)
            Text(verbatim: "\(match.scoreA)-\(match.scoreB)")
                .font(.watchScore(17))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
    }
}

/// Score in the corner, with a curved progress gauge (or the court) along the bezel.
private struct ComplicationCorner: View {
    let match: ActiveMatchSnapshot

    var body: some View {
        let score = Text(verbatim: "\(match.scoreA)–\(match.scoreB)")
            .font(.watchScore(18))
            .widgetAccentable()
        if let progress = match.gaugeProgress {
            score.widgetLabel {
                Gauge(value: progress) {
                    Text("Court \(match.court)")
                }
                .tint(WatchPalette.lime)
            }
        } else {
            score.widgetLabel { Text("Court \(match.court)") }
        }
    }
}

/// Thin progress rail: track plus lime fill with a ball at its head.
struct ComplicationRail: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fill = max(4, width * min(1, max(0, progress)))
            ZStack(alignment: .leading) {
                Capsule().fill(WatchPalette.chalk.opacity(0.18))
                Capsule().fill(WatchPalette.lime).frame(width: fill)
                    .widgetAccentable()
                Circle().fill(WatchPalette.chalk)
                    .frame(width: 5, height: 5)
                    .offset(x: fill - 5)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// A padel ball: white disc with the seam curve, drawn so it tints in accented faces.
struct ComplicationBall: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(WatchPalette.lime)
            WatchBallSeam()
                .stroke(WatchPalette.onLime.opacity(0.55), style: StrokeStyle(lineWidth: max(1, size / 14), lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The curved seam of a tennis/padel ball.
struct WatchBallSeam: Shape {
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
