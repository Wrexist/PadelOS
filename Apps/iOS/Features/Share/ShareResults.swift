import SwiftUI
import UIKit
import PadelCore

/// Share sheet with a rendered standings card and a text summary. Everything is produced
/// on the device; nothing is uploaded.
struct ShareResultsButton: View {
    let tournament: Tournament
    let standings: Standings
    @Environment(\.displayScale) private var displayScale
    @State private var cardImage: Image?

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let cardImage {
                ShareLink(
                    item: cardImage,
                    message: Text(ResultSummary.text(for: tournament, standings: standings)),
                    preview: SharePreview("\(tournament.name) standings", image: cardImage)
                ) {
                    Label("Share Results", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.padelPrimary)
                .accessibilityIdentifier("shareResultsButton")
            }
            ShareLink(item: ResultSummary.resultsText(for: tournament)) {
                Label("Share All Match Results as Text", systemImage: "text.alignleft")
            }
            .buttonStyle(.padelSecondary)
        }
        .task(id: standings) { await render() }
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content: ShareCard(tournament: tournament, standings: standings).frame(width: 390))
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            cardImage = Image(uiImage: uiImage)
        }
    }
}

/// The image shared with friends. Always dark for a consistent look in chats.
struct ShareCard: View {
    let tournament: Tournament
    let standings: Standings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                BrandMark()
                Spacer()
                Text(tournament.status == .completed ? "FINAL" : "LIVE")
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: 0xC7F36B), in: Capsule())
                    .foregroundStyle(Color(hex: 0x101210))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(tournament.name)
                    .font(.title2.weight(.bold))
                Text("\(tournament.configuration.format.displayName) · \(tournament.configuration.scoring.displayName) · \(tournament.progressLabel)")
                    .font(.footnote)
                    .foregroundStyle(Color(hex: 0x8B928A))
            }
            VStack(spacing: 0) {
                ForEach(standings.entries.prefix(12)) { entry in
                    HStack {
                        Text(entry.isTied ? "=\(entry.rank)" : "\(entry.rank)")
                            .frame(width: 30, alignment: .leading)
                            .foregroundStyle(entry.rank == 1 ? Color(hex: 0xC7F36B) : Color(hex: 0x8B928A))
                        Text(entry.name).lineLimit(1)
                        Spacer()
                        Text("\(entry.wins)W").foregroundStyle(Color(hex: 0x8B928A)).frame(width: 36, alignment: .trailing)
                        Text("\(entry.points)").fontWeight(.bold).frame(width: 44, alignment: .trailing)
                    }
                    .font(.subheadline.monospacedDigit())
                    .padding(.vertical, 7)
                    if entry.id != standings.entries.prefix(12).last?.id {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    }
                }
            }
            if standings.entries.count > 12 {
                Text("+ \(standings.entries.count - 12) more")
                    .font(.footnote)
                    .foregroundStyle(Color(hex: 0x8B928A))
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(Color(hex: 0x101210))
        .environment(\.colorScheme, .dark)
    }
}
