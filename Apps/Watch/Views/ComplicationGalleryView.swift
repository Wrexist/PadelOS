import SwiftUI
import WidgetKit

/// Demo only (`-demo-scenario complications`): draws every complication family with
/// sample data so CI can screenshot them; the simulator cannot put them on a face.
struct ComplicationGalleryView: View {
    private let points = ActiveMatchSnapshot.preview
    private let sets = ActiveMatchSnapshot(tournamentName: "Friday Padel", roundLabel: "R3/6", court: 2, teamA: "Erik/Sofia", teamB: "Daniel/Fredrik", scoreA: 4, scoreB: 3, total: nil, isFinished: false, roundProgress: 0.45, situation: "Deuce")

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                tile(.accessoryRectangular, points, width: 166, height: 72)
                tile(.accessoryRectangular, sets, width: 166, height: 72)
                HStack(spacing: 8) {
                    tile(.accessoryCircular, points, width: 54, height: 54)
                    tile(.accessoryCircular, sets, width: 54, height: 54)
                    tile(.accessoryCorner, points, width: 54, height: 54)
                }
                tile(.accessoryInline, points, width: 166, height: 22)
                tile(.accessoryRectangular, nil, width: 166, height: 60)
            }
            .padding(.horizontal, 4)
        }
    }

    private func tile(_ family: WidgetFamily, _ snapshot: ActiveMatchSnapshot?, width: CGFloat, height: CGFloat) -> some View {
        ActiveMatchComplicationView(family: family, snapshot: snapshot)
            .frame(width: width, height: height)
            .padding(6)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.15)))
    }
}
