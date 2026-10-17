import SwiftUI
import PadelCore
import PadelStore

/// Full standings. Rows slide to their new place when results change, bars grow in from
/// the left on appear, and arrows show movement since the previous round.
struct WatchStandingsView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tournamentID: TournamentID
    @State private var appeared = false

    var body: some View {
        ScrollView {
            if let tournament = store.state.tournament(tournamentID) {
                let standings = StandingsCalculator.compute(tournament)
                let movement = Self.movement(in: tournament, current: standings)
                let leader = max(1, standings.entries.first?.points ?? 1)
                LazyVStack(spacing: 5) {
                    ForEach(Array(standings.entries.enumerated()), id: \.element.id) { index, entry in
                        StandingRow(
                            entry: entry,
                            movement: movement[entry.id] ?? 0,
                            share: Double(entry.points) / Double(leader),
                            shown: appeared,
                            delay: Double(min(index, 10)) * 0.04
                        )
                    }
                    if standings.entries.isEmpty {
                        Text("Standings appear as soon as the first match is finished.")
                            .font(.footnote)
                            .foregroundStyle(WatchPalette.muted)
                    }
                }
                .animation(WatchMotion.resolve(WatchMotion.settle, reduceMotion: reduceMotion), value: standings.entries.map(\.id))
                .padding(.horizontal, 2)
            }
        }
        .navigationTitle("Standings")
        .containerBackground(WatchHomeView.background(WatchPalette.chalk.opacity(0.12)), for: .navigation)
        .onAppear { appeared = true }
    }

    /// Places gained (+) or lost (−) since the round before the last completed one.
    static func movement(in tournament: Tournament, current: Standings) -> [StandingSubject: Int] {
        let completed = tournament.rounds.filter { $0.kind != .knockout && $0.isCompleted }.map(\.number)
        guard let last = completed.max(), last >= 2 else { return [:] }
        let previous = StandingsCalculator.compute(tournament, throughRound: last - 1)
        var result: [StandingSubject: Int] = [:]
        for entry in current.entries {
            if let before = previous.entry(for: entry.id) { result[entry.id] = before.rank - entry.rank }
        }
        return result
    }
}

private struct StandingRow: View {
    let entry: StandingEntry
    let movement: Int
    let share: Double
    let shown: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            WatchRankBadge(rank: entry.rank, isTied: entry.isTied, size: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Text(entry.name)
                        .font(.watchLabel(.footnote, weight: entry.rank == 1 ? .heavy : .semibold))
                        .foregroundStyle(entry.isWithdrawn ? WatchPalette.muted : WatchPalette.chalk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if movement != 0 {
                        HStack(spacing: 0) {
                            Image(systemName: movement > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(size: 6))
                            Text(verbatim: "\(abs(movement))")
                        }
                        .font(.system(size: 9, weight: .heavy).monospacedDigit())
                        .foregroundStyle(movement > 0 ? WatchPalette.lime : WatchPalette.danger)
                        .accessibilityHidden(true)
                    }
                }
                GeometryReader { proxy in
                    Capsule()
                        .fill(entry.rank == 1 ? WatchPalette.lime : WatchPalette.chalk.opacity(0.35))
                        .frame(width: max(3, proxy.size.width * (shown ? min(1, max(0, share)) : 0)))
                }
                .frame(height: 3)
                .animation(WatchMotion.resolve(WatchMotion.settle.delay(delay), reduceMotion: reduceMotion), value: shown)
                .accessibilityHidden(true)
            }
            Text(verbatim: "\(entry.points)")
                .font(.watchScore(22))
                .foregroundStyle(entry.rank == 1 ? WatchPalette.lime : WatchPalette.chalk)
                .contentTransition(.numericText(value: Double(entry.points)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(WatchPalette.surface.opacity(entry.rank <= 3 ? 0.95 : 0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Gold, silver and bronze discs for the top three; a plain number below.
struct WatchRankBadge: View {
    let rank: Int
    let isTied: Bool
    var size: CGFloat = 22

    var body: some View {
        let medal: Color? = switch rank {
        case 1: WatchPalette.lime
        case 2: WatchPalette.silver
        case 3: WatchPalette.bronze
        default: nil
        }
        Text(isTied ? "=\(rank)" : "\(rank)")
            .font(.watchScore(size * 0.62, weight: .black))
            .foregroundStyle(medal == nil ? WatchPalette.muted : WatchPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .background(medal ?? Color.clear, in: Circle())
            .overlay(Circle().stroke(WatchPalette.chalk.opacity(medal == nil ? 0.2 : 0), lineWidth: 1))
    }
}

extension WatchPalette {
    static let danger = rgb(0xFF6B5E)
}
