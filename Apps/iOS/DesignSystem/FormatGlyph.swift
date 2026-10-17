import SwiftUI
import PadelCore

/// A tiny top-down court that explains a format at a glance: who stands where, which
/// players are a fixed team, and what drives the next round (rotation, ranking, ladder).
struct FormatGlyph: View {
    let format: TournamentFormat
    var isSelected = false
    var size = CGSize(width: 70, height: 46)

    var body: some View {
        ZStack {
            MiniCourtShape()
                .stroke(isSelected ? Theme.Colors.accentText : Theme.Colors.textSecondary.opacity(0.7), lineWidth: 1.2)
            if format.usesTeams {
                teamLinks
            }
            ForEach(0..<4, id: \.self) { index in
                dot(index)
            }
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(width: 20, height: 20)
                .background(Theme.Colors.accent, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Colors.background, lineWidth: 2))
                .offset(x: size.width / 2 - 4, y: size.height / 2 - 4)
                .scaleEffect(isSelected ? 1.12 : 1)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch format {
        case .americano, .mixedAmericano: "arrow.triangle.2.circlepath"
        case .mexicano, .mixicano, .teamMexicano: "chart.bar.fill"
        case .teamAmericano: "person.2.fill"
        case .swiss: "scalemass.fill"
        case .kingOfTheCourt: "crown.fill"
        }
    }

    /// Two players per half: left half is one team, right half the other.
    private func position(_ index: Int) -> CGPoint {
        let x = index < 2 ? size.width * 0.27 : size.width * 0.73
        let y = index.isMultiple(of: 2) ? size.height * 0.3 : size.height * 0.7
        return CGPoint(x: x, y: y)
    }

    private func dot(_ index: Int) -> some View {
        let secondGroup = format.usesGroups && index.isMultiple(of: 2)
        let ranked = format == .mexicano || format == .mixicano
        return ZStack {
            Circle()
                .fill(secondGroup ? Theme.Colors.textPrimary : Theme.Colors.accentText)
            if ranked {
                // Mexicano pairs 1 & 4 against 2 & 3.
                Text(verbatim: ["1", "4", "2", "3"][index])
                    .font(.system(size: 7, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.Colors.background)
            }
        }
        .frame(width: 11, height: 11)
        .position(position(index))
    }

    private var teamLinks: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { team in
                let top = position(team * 2)
                Capsule()
                    .strokeBorder(Theme.Colors.accentText.opacity(0.7), lineWidth: 1.2)
                    .frame(width: 17, height: size.height * 0.4 + 17)
                    .position(x: top.x, y: size.height / 2)
            }
        }
    }
}

/// Outline, net and service lines of a court seen from above, net vertical.
struct MiniCourtShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 5)
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 1))
        for x in [rect.width * 0.2, rect.width * 0.8] {
            path.move(to: CGPoint(x: rect.minX + x, y: rect.minY + 1))
            path.addLine(to: CGPoint(x: rect.minX + x, y: rect.maxY - 1))
        }
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.8, y: rect.midY))
        return path
    }
}
