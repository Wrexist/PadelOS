import SwiftUI
import WidgetKit

struct ActiveMatchEntry: TimelineEntry {
    let date: Date
    let snapshot: ActiveMatchSnapshot?

    /// Smart Stack: a match in progress is highly relevant for the next hours; an idle
    /// or finished one is not.
    var relevance: TimelineEntryRelevance? {
        guard let snapshot, !snapshot.isFinished else { return TimelineEntryRelevance(score: 0) }
        return TimelineEntryRelevance(score: snapshot.isLive ? 100 : 40, duration: 3 * 60 * 60)
    }
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
        ActiveMatchComplicationView(family: family, snapshot: entry.snapshot)
    }
}

struct ActiveMatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ActiveMatch", provider: ActiveMatchProvider()) { entry in
            ActiveMatchWidgetView(entry: entry)
                // Shown in the Smart Stack; watch faces remove it.
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [WatchPalette.turf, WatchPalette.ink], startPoint: .top, endPoint: .bottom)
                }
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
