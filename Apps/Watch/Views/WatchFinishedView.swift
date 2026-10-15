import SwiftUI
import PadelCore
import PadelStore

/// Match won: the trophy lands, confetti bursts, the final score settles in.
struct WatchFinishedView: View {
    @Environment(WatchModel.self) private var model
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let tournament: Tournament
    let match: Match
    @Binding var path: [WatchRoute]
    @State private var appeared = false

    private var isSets: Bool { tournament.scoringRule(for: match).isSets }
    private var winner: TeamSide? { ScoringEngine.winner(of: match) }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [WatchPalette.lime.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 44))
                        .frame(width: 88, height: 88)
                        .scaleEffect(appeared ? 1 : 0.2)
                        .opacity(isLuminanceReduced ? 0 : 1)
                    Image(systemName: winner == nil ? "equal.circle.fill" : "trophy.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(winner == nil ? WatchPalette.chalk : WatchPalette.gold)
                        .symbolEffect(.bounce, value: appeared)
                        .scaleEffect(appeared ? 1 : 0.3)
                        .rotationEffect(.degrees(appeared ? 0 : -25))
                }
                .frame(height: 64)
                .accessibilityHidden(true)

                WatchOverline(text: String(localized: "Match Finished"), color: WatchPalette.lime)
                    .watchReveal(appeared, delay: 0.1, reduceMotion: reduceMotion)

                scoreLine
                    .watchReveal(appeared, delay: 0.16, reduceMotion: reduceMotion)

                Text(winnerText)
                    .font(.watchLabel(.footnote, weight: .bold))
                    .foregroundStyle(WatchPalette.chalk.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .watchReveal(appeared, delay: 0.22, reduceMotion: reduceMotion)

                if let next = model.activeMatch(in: tournament), next.id != match.id {
                    Button {
                        model.selectedMatchID = next.id
                        path = [.scoring(tournament.id, next.id)]
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Next: Court \(next.court)\(next.roundNumber != match.roundNumber ? " · R\(next.roundNumber)" : "")")
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .font(.watchLabel(.body, weight: .heavy))
                        .foregroundStyle(WatchPalette.onLime)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(WatchPalette.lime, in: Capsule())
                    }
                    .buttonStyle(WatchPressableStyle())
                    .doubleTapShortcut(true)
                    .watchReveal(appeared, delay: 0.3, reduceMotion: reduceMotion)
                    .padding(.top, 4)
                }
                Button {
                    path.removeAll()
                } label: {
                    Text("Done")
                        .font(.watchLabel(.body, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(WatchPalette.raised, in: Capsule())
                }
                .buttonStyle(WatchPressableStyle())
                .accessibilityIdentifier("watchDone")
                .watchReveal(appeared, delay: 0.34, reduceMotion: reduceMotion)
                if !match.isLogCompacted && tournament.status == .active {
                    Button("Reopen Match") {
                        _ = store.reopen(match: match.id, tournament: tournament.id)
                    }
                    .buttonStyle(.plain)
                    .font(.footnote)
                    .foregroundStyle(WatchPalette.muted)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 4)
        }
        .background {
            RadialGradient(colors: [WatchPalette.lime.opacity(isLuminanceReduced ? 0 : 0.28), WatchPalette.ink.opacity(0)], center: .top, startRadius: 0, endRadius: 200)
                .ignoresSafeArea()
        }
        .overlay {
            if !reduceMotion && !isLuminanceReduced && winner != nil {
                WatchConfetti(origin: UnitPoint(x: 0.5, y: 0.22))
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? WatchMotion.fade : WatchMotion.pop) { appeared = true }
        }
    }

    private var scoreLine: some View {
        Text(isSets ? match.resultText(rule: tournament.scoringRule(for: match)) : "\(match.score.a) – \(match.score.b)")
            .font(.watchScore(isSets ? 30 : 52))
            .foregroundStyle(WatchPalette.chalk)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .accessibilityLabel("Final score \(match.resultText(rule: tournament.scoringRule(for: match)))")
    }

    private var winnerText: String {
        guard let winner else { return String(localized: "Draw") }
        return String(localized: "\(tournament.sideNames(of: match, winner).joined(separator: " & ")) win")
    }
}

private struct WatchReveal: ViewModifier {
    let shown: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .animation((reduceMotion ? WatchMotion.fade : WatchMotion.settle).delay(reduceMotion ? 0 : delay), value: shown)
    }
}

extension View {
    /// Fades and lifts the view in once `shown` becomes true, after `delay`.
    func watchReveal(_ shown: Bool, delay: Double, reduceMotion: Bool) -> some View {
        modifier(WatchReveal(shown: shown, delay: delay, reduceMotion: reduceMotion))
    }
}
