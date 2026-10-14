import SwiftUI
import WidgetKit

struct ActiveMatchEntry: TimelineEntry {
    let date: Date
    let snapshot: ActiveMatchSnapshot?
}

/// The watch app reloads timelines whenever the active match changes, so a single entry
/// with `.never` refresh is enough; no polling or background work.
struct ActiveMatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActiveMatchEntry {
        ActiveMatchEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (ActiveMatchEntry) -> Void) {
        completion(ActiveMatchEntry(date: Date(), snapshot: context.isPreview ? .preview : ActiveMatchSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveMatchEntry>) -> Void) {
        completion(Timeline(entries: [ActiveMatchEntry(date: Date(), snapshot: ActiveMatchSnapshot.load())], policy: .never))
    }
}

struct ActiveMatchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ActiveMatchEntry

    var body: some View {
        if let match = entry.snapshot {
            content(match)
        } else {
            empty
        }
    }

    @ViewBuilder
    private func content(_ match: ActiveMatchSnapshot) -> some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Court \(match.court) · \(match.roundLabel)\(match.isFinished ? " · Final" : "")")
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                row(match.teamA, match.scoreA)
                row(match.teamB, match.scoreB)
            }
        case .accessoryCircular:
            if let total = match.total {
                Gauge(value: Double(min(total, match.scoreA + match.scoreB)), in: 0...Double(max(1, total))) {
                    Text("C\(match.court)")
                } currentValueLabel: {
                    Text("\(match.scoreA)-\(match.scoreB)").monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else {
                VStack(spacing: 0) {
                    Text("C\(match.court)").font(.caption2)
                    Text("\(match.scoreA)-\(match.scoreB)").font(.headline).monospacedDigit()
                }
            }
        case .accessoryCorner:
            Text("\(match.scoreA)–\(match.scoreB)")
                .monospacedDigit()
                .widgetLabel("Court \(match.court)")
        default:
            Text("Court \(match.court) \(match.scoreA)–\(match.scoreB)")
        }
    }

    private func row(_ name: String, _ score: Int) -> some View {
        HStack {
            Text(name).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(score)").font(.headline).monospacedDigit()
        }
        .font(.caption)
    }

    @ViewBuilder
    private var empty: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("PadelOS").font(.headline).widgetAccentable()
                Text("No active match").font(.caption)
            }
        case .accessoryInline:
            Text("PadelOS")
        default:
            Image(systemName: "sportscourt").font(.title3).widgetAccentable()
        }
    }
}

struct ActiveMatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ActiveMatch", provider: ActiveMatchProvider()) { entry in
            ActiveMatchWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Active Match")
        .description("Court and score of the match you are scoring. Tap to open.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

@main
struct PadelWidgets: WidgetBundle {
    var body: some Widget {
        ActiveMatchWidget()
    }
}
