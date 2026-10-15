import SwiftUI
import PadelCore
import PadelStore

/// Home: vertical pages you flick through with the Digital Crown. First the match you
/// are scoring (or the podium once the tournament is over), then every other court of
/// the round, then the standings.
struct WatchHomeView: View {
    @Environment(WatchModel.self) private var model
    @Environment(WatchStore.self) private var store
    @Binding var path: [WatchRoute]

    var body: some View {
        if let tournament = model.tournament {
            let active = model.activeMatch(in: tournament)
            let others = (tournament.currentRound?.matches ?? []).filter { $0.id != active?.id }
            TabView {
                if tournament.status == .completed || (tournament.allRoundsCompleted && active == nil) {
                    PodiumPage(tournament: tournament)
                        .containerBackground(Self.background(WatchPalette.gold.opacity(0.35)), for: .tabView)
                } else {
                    NowPage(tournament: tournament, active: active, path: $path)
                        .containerBackground(Self.background(WatchPalette.lime.opacity(0.32)), for: .tabView)
                }
                ForEach(others) { match in
                    CourtPage(tournament: tournament, match: match, path: $path)
                        .containerBackground(Self.background(WatchPalette.lime.opacity(match.status == .inProgress ? 0.2 : 0.1)), for: .tabView)
                }
                StandingsPage(tournament: tournament)
                    .containerBackground(Self.background(WatchPalette.chalk.opacity(0.14)), for: .tabView)
                if store.tournaments.count > 1 {
                    OtherTournamentsPage(current: tournament)
                        .containerBackground(Self.background(WatchPalette.chalk.opacity(0.08)), for: .tabView)
                }
            }
            .tabViewStyle(.verticalPage)
        } else {
            EmptyHomePage()
                .containerBackground(Self.background(WatchPalette.lime.opacity(0.22)), for: .navigation)
        }
    }

    static func background(_ glow: Color) -> LinearGradient {
        LinearGradient(colors: [glow, WatchPalette.ink], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Now

private struct NowPage: View {
    @Environment(WatchModel.self) private var model
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tournament: Tournament
    let active: Match?
    @Binding var path: [WatchRoute]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WatchOverline(text: tournament.name, color: WatchPalette.lime)
                .padding(.trailing, 48)
            HStack(spacing: 4) {
                Text(tournament.progressLabel)
                    .font(.watchLabel(.headline, weight: .heavy))
                    .foregroundStyle(WatchPalette.chalk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Spacer(minLength: 2)
                WatchSyncChip(status: store.syncStatus)
            }
            RoundRail(progress: tournament.progressFraction)

            Spacer(minLength: 0)

            Group {
                if let active {
                    Button {
                        model.selectedMatchID = active.id
                        path.append(.scoring(tournament.id, active.id))
                    } label: {
                        WatchMatchCard(tournament: tournament, match: active, prominent: true)
                    }
                    .buttonStyle(WatchPressableStyle())
                    .accessibilityIdentifier("watchActiveMatch")
                    .accessibilityLabel(tournament.accessibilityDescription(of: active))
                    .accessibilityHint(active.hasStarted ? String(localized: "Active Match") : String(localized: "Start Match"))
                    .id(active.id)
                    .transition(.asymmetric(insertion: .push(from: .bottom), removal: .push(from: .top)))
                } else {
                    StatusCard(
                        symbol: tournament.allRoundsCompleted ? "flag.checkered" : "iphone",
                        text: tournament.allRoundsCompleted ? String(localized: "All rounds played") : String(localized: "Waiting for iPhone to draw the next round")
                    )
                }
            }
            .animation(WatchMotion.resolve(WatchMotion.settle, reduceMotion: reduceMotion), value: active?.id)
            .animation(WatchMotion.resolve(WatchMotion.settle, reduceMotion: reduceMotion), value: tournament.currentRound?.number)

            if case .pending(_, let reachable) = store.syncStatus, !reachable {
                Text("Sent when iPhone is nearby")
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
    }
}

/// Tournament progress rail with a ball at its head.
private struct RoundRail: View {
    let progress: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let fill = max(6, proxy.size.width * (shown ? progress : 0))
            ZStack(alignment: .leading) {
                Capsule().fill(WatchPalette.chalk.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: [WatchPalette.lime.opacity(0.6), WatchPalette.lime], startPoint: .leading, endPoint: .trailing))
                    .frame(width: fill)
                WatchBall(size: 8)
                    .offset(x: fill - 8)
            }
        }
        .frame(height: 8)
        .onAppear {
            withAnimation(WatchMotion.resolve(WatchMotion.settle.delay(0.15), reduceMotion: reduceMotion)) { shown = true }
        }
        .animation(WatchMotion.resolve(WatchMotion.settle, reduceMotion: reduceMotion), value: progress)
        .accessibilityHidden(true)
    }
}

// MARK: - Cards

/// Court, status and both teams with their scores.
struct WatchMatchCard: View {
    let tournament: Tournament
    let match: Match
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: prominent ? 4 : 3) {
            HStack(spacing: 5) {
                Text("Court \(match.court)")
                    .font(.watchLabel(prominent ? .footnote : .caption2, weight: .heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(WatchPalette.lime)
                Spacer(minLength: 2)
                WatchMatchStatusBadge(match: match)
            }
            teamRow(.a)
            teamRow(.b)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, prominent ? 9 : 7)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(WatchPalette.surface.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(WatchPalette.lime.opacity(match.status == .inProgress ? 0.55 : 0.12), lineWidth: 1)
                }
        }
    }

    private func teamRow(_ side: TeamSide) -> some View {
        let leads = match.hasStarted && match.score[side] > match.score[side.opposite]
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(tournament.sideNames(of: match, side).joined(separator: " / "))
                .font(.watchLabel(prominent ? .body : .footnote, weight: leads ? .heavy : .semibold))
                .foregroundStyle(side == .a ? WatchPalette.chalk : WatchPalette.chalk.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            if match.hasStarted {
                Text(verbatim: "\(match.score[side])")
                    .font(.watchScore(prominent ? 30 : 22))
                    .foregroundStyle(side == .a ? WatchPalette.lime : WatchPalette.chalk)
                    .contentTransition(.numericText(value: Double(match.score[side])))
            }
        }
        .animation(WatchMotion.pop, value: match.score)
    }
}

/// LIVE (pulsing), Up next, or Finished.
struct WatchMatchStatusBadge: View {
    let match: Match

    var body: some View {
        HStack(spacing: 4) {
            switch match.status {
            case .inProgress:
                WatchLiveDot(size: 6)
                Text("LIVE")
            case .scheduled:
                Text("Up next")
            case .completed:
                Image(systemName: "checkmark")
                Text("Finished")
            }
        }
        .font(.watchLabel(.caption2, weight: .heavy))
        .textCase(.uppercase)
        .foregroundStyle(match.status == .inProgress ? WatchPalette.lime : WatchPalette.muted)
        .accessibilityHidden(true)
    }
}

private struct StatusCard: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(WatchPalette.lime)
                .symbolEffect(.pulse)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(WatchPalette.chalk.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchPalette.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Court page

private struct CourtPage: View {
    @Environment(WatchModel.self) private var model
    let tournament: Tournament
    let match: Match
    @Binding var path: [WatchRoute]

    var body: some View {
        Button {
            model.selectedMatchID = match.id
            path.append(.scoring(tournament.id, match.id))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                WatchOverline(text: tournament.currentRound.map { tournament.roundTitle($0) } ?? "")
                Spacer(minLength: 0)
                WatchMatchCard(tournament: tournament, match: match)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(alignment: .topTrailing) {
                // Giant court number watermark.
                Text(verbatim: "\(match.court)")
                    .font(.watchScore(110, weight: .black))
                    .foregroundStyle(WatchPalette.lime.opacity(0.13))
                    .offset(x: 4, y: -10)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(WatchPressableStyle())
        .padding(.horizontal, 4)
        .accessibilityLabel(tournament.accessibilityDescription(of: match))
    }
}

// MARK: - Standings page

private struct StandingsPage: View {
    let tournament: Tournament

    var body: some View {
        let entries = Array(StandingsCalculator.compute(tournament).entries.prefix(4))
        NavigationLink(value: WatchRoute.standings(tournament.id)) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    WatchOverline(text: String(localized: "Standings"), color: WatchPalette.lime)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WatchPalette.muted)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 6) {
                        WatchRankBadge(rank: entry.rank, isTied: entry.isTied, size: 20)
                        Text(entry.name)
                            .font(.watchLabel(.footnote, weight: index == 0 ? .heavy : .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(verbatim: "\(entry.points)")
                            .font(.watchScore(18))
                            .foregroundStyle(index == 0 ? WatchPalette.lime : WatchPalette.chalk)
                    }
                    .accessibilityElement(children: .combine)
                }
                if entries.isEmpty {
                    Text("Standings appear as soon as the first match is finished.")
                        .font(.footnote)
                        .foregroundStyle(WatchPalette.muted)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}

// MARK: - Podium

/// The finished tournament: top three rise onto the podium, confetti falls.
private struct PodiumPage: View {
    let tournament: Tournament
    @State private var risen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private struct Place: Identifiable {
        let rank: Int
        let name: String
        var id: Int { rank }
    }

    private var places: [Place] {
        if let champion = tournament.playoffChampion {
            var result = [Place(rank: 1, name: tournament.sideName(champion))]
            if let runnerUp = tournament.playoffRunnerUp { result.append(Place(rank: 2, name: tournament.sideName(runnerUp))) }
            return result
        }
        return StandingsCalculator.compute(tournament).entries.prefix(3).enumerated().map { Place(rank: $0.offset + 1, name: $0.element.name) }
    }

    var body: some View {
        VStack(spacing: 4) {
            WatchOverline(text: String(localized: "Tournament finished"), color: WatchPalette.gold)
            Text(tournament.name)
                .font(.watchLabel(.footnote, weight: .bold))
                .foregroundStyle(WatchPalette.chalk.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 2)
            GeometryReader { proxy in
                let order = places.sorted { podiumOrder($0.rank) < podiumOrder($1.rank) }
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(order) { place in
                        column(place, maxHeight: proxy.size.height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .padding(.horizontal, 4)
        .overlay {
            if !reduceMotion && !isLuminanceReduced {
                WatchConfetti(count: 36, origin: UnitPoint(x: 0.5, y: 0.35))
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            withAnimation(WatchMotion.resolve(WatchMotion.settle, reduceMotion: reduceMotion)) { risen = true }
        }
        .accessibilityElement(children: .combine)
    }

    /// 2nd on the left, 1st in the middle, 3rd on the right.
    private func podiumOrder(_ rank: Int) -> Int { rank == 1 ? 1 : (rank == 2 ? 0 : 2) }

    private func column(_ place: Place, maxHeight: CGFloat) -> some View {
        let available = max(40, maxHeight - 42)
        let height = available * (place.rank == 1 ? 0.85 : (place.rank == 2 ? 0.62 : 0.44))
        let color = place.rank == 1 ? WatchPalette.gold : (place.rank == 2 ? WatchPalette.silver : WatchPalette.bronze)
        return VStack(spacing: 3) {
            if place.rank == 1 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WatchPalette.gold)
                    .symbolEffect(.bounce, value: risen)
                    .accessibilityHidden(true)
            }
            Text(place.name)
                .font(.watchLabel(.caption2, weight: .heavy))
                .foregroundStyle(WatchPalette.chalk)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [color, color.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                Text(verbatim: "\(place.rank)")
                    .font(.watchScore(26, weight: .black))
                    .foregroundStyle(WatchPalette.ink)
                    .padding(.top, 2)
            }
            .frame(height: risen ? height : 6)
            .animation(WatchMotion.resolve(WatchMotion.pop.delay(Double(3 - place.rank) * 0.12 + 0.1), reduceMotion: reduceMotion), value: risen)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Other tournaments

private struct OtherTournamentsPage: View {
    @Environment(WatchModel.self) private var model
    @Environment(WatchStore.self) private var store
    let current: Tournament

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                WatchOverline(text: String(localized: "Other tournaments"), color: WatchPalette.lime)
                ForEach(store.tournaments.filter { $0.id != current.id }) { other in
                    Button {
                        if let match = model.activeMatch(in: other) ?? other.currentRound?.matches.first {
                            model.selectedMatchID = match.id
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(other.name)
                                .font(.watchLabel(.body, weight: .heavy))
                                .lineLimit(1)
                            Text(other.progressLabel)
                                .font(.caption2)
                                .foregroundStyle(WatchPalette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(WatchPalette.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(WatchPressableStyle())
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Empty

/// Before the first tournament: an iPhone beaming a ball to the watch.
private struct EmptyHomePage: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "iphone.gen3")
                        .font(.title2)
                    GeometryReader { proxy in
                        WatchBall(size: 9)
                            .phaseAnimator(reduceMotion ? [0.5] : [0.0, 1.0]) { content, t in
                                content.position(x: 5 + (proxy.size.width - 10) * t, y: proxy.size.height / 2 - sin(t * .pi) * 8)
                            } animation: { t in
                                t == 0 ? .easeIn(duration: 0.01) : .easeInOut(duration: 1.1)
                            }
                    }
                    .frame(height: 24)
                    Image(systemName: "applewatch")
                        .font(.title2)
                        .foregroundStyle(WatchPalette.lime)
                }
                .foregroundStyle(WatchPalette.chalk)
                .accessibilityHidden(true)

                Text("Create a tournament on your iPhone")
                    .font(.watchLabel(.headline, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                Text("It appears here automatically. Then you can score without your phone.")
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                WatchSyncChip(status: store.syncStatus)
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Courts (Switch Court)

struct WatchCourtsView: View {
    @Environment(WatchModel.self) private var model
    @Environment(WatchStore.self) private var store
    let tournamentID: TournamentID
    @Binding var path: [WatchRoute]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let tournament = store.state.tournament(tournamentID) {
                    let rounds = tournament.rounds.filter { !$0.isCompleted }.prefix(2)
                    ForEach(Array(rounds)) { round in
                        WatchOverline(text: tournament.roundTitle(round), color: WatchPalette.lime)
                            .padding(.top, 4)
                        ForEach(round.matches) { match in
                            Button {
                                model.selectedMatchID = match.id
                                path.append(.scoring(tournamentID, match.id))
                            } label: {
                                WatchMatchCard(tournament: tournament, match: match)
                            }
                            .buttonStyle(WatchPressableStyle())
                            .accessibilityLabel(tournament.accessibilityDescription(of: match))
                        }
                    }
                    if rounds.isEmpty {
                        Text("No matches left to play.")
                            .font(.footnote)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Courts")
    }
}
