import SwiftUI
import PadelCore
import PadelStore

struct TournamentView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case live = "Live"
        case schedule = "Schedule"
        case standings = "Standings"
        var id: String { rawValue }

        var title: String {
            switch self {
            case .live: String(localized: "Live")
            case .schedule: String(localized: "Schedule")
            case .standings: String(localized: "Standings")
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(TournamentStore.self) private var store
    let tournamentID: TournamentID
    @Binding var path: [Route]
    @State private var tab: Tab = .live
    @State private var showManage = false
    @State private var showConflicts = false
    @State private var resultEntry: MatchID?
    @State private var confirmFinish = false

    var body: some View {
        Group {
            if let tournament = store.tournament(tournamentID) {
                content(tournament)
            } else {
                EmptyStateView(symbol: "questionmark.folder", title: "Tournament not found", message: "It may have been deleted.")
            }
        }
        .screenBackground()
    }

    @ViewBuilder
    private func content(_ tournament: Tournament) -> some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.s)
            .accessibilityIdentifier("tournamentTabs")

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if let message = model.errorMessage {
                        MessageBanner(style: .error, message: message, onDismiss: { model.errorMessage = nil })
                    }
                    if tournament.openConflictCount > 0 {
                        MessageBanner(
                            style: .warning,
                            message: String(localized: "\(tournament.openConflictCount) score changes from Apple Watch could not be applied."),
                            actionTitle: String(localized: "Review"),
                            action: { showConflicts = true }
                        )
                    }
                    switch tab {
                    case .live: LiveTab(tournament: tournament, path: $path, resultEntry: $resultEntry, confirmFinish: $confirmFinish)
                    case .schedule: ScheduleTab(tournament: tournament, path: $path, resultEntry: $resultEntry)
                    case .standings: StandingsTab(tournament: tournament)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .navigationTitle(tournament.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(tournament.name).font(.headline).foregroundStyle(Theme.Colors.textPrimary)
                    Text(tournament.summaryLine).font(.caption2).foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: ResultSummary.text(for: tournament)) {
                        Label("Share Standings", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showManage = true
                    } label: {
                        Label("Manage Tournament", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("manageTournamentButton")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("tournamentMenu")
            }
        }
        .sheet(isPresented: $showManage) {
            ManageTournamentView(tournamentID: tournamentID) {
                showManage = false
                path.removeAll()
            }
        }
        .sheet(isPresented: $showConflicts) {
            ConflictsView(tournamentID: tournamentID)
        }
        .sheet(item: Binding(get: { resultEntry.map { IdentifiedMatch(id: $0) } }, set: { resultEntry = $0?.id })) { item in
            ResultEntrySheet(tournamentID: tournamentID, matchID: item.id)
        }
        .confirmationDialog("Finish tournament?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish Tournament") {
                model.run { try store.perform(tournamentID) { (t, c) throws(TournamentError) in t.finish(now: c.now) } }
                tab = .standings
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Final standings are locked. You can reopen the tournament later.")
        }
    }
}

struct IdentifiedMatch: Identifiable {
    let id: MatchID
}

// MARK: - Live

struct LiveTab: View {
    @Environment(AppModel.self) private var model
    let tournament: Tournament
    @Binding var path: [Route]
    @Binding var resultEntry: MatchID?
    @Binding var confirmFinish: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Text(tournament.progressLabel)
                        .font(.padelSection)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let round = tournament.currentRound, round.kind == .final || round.kind == .knockout {
                        Text(round.kind == .knockout ? "PLAYOFFS" : "FINAL")
                            .font(.caption.weight(.heavy))
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.vertical, 2)
                            .foregroundStyle(Theme.Colors.onAccent)
                            .background(Theme.Colors.accent, in: Capsule())
                    }
                }
                ProgressBar(value: tournament.progressFraction)
            }
            .padding(.top, Theme.Spacing.s)

            if tournament.status == .completed {
                completedCard
            } else if let round = tournament.currentRound {
                ForEach(round.matches) { match in
                    MatchCard(tournament: tournament, match: match, onOpen: {
                        path.append(.match(tournament.id, match.id))
                    }, onEnterResult: {
                        resultEntry = match.id
                    })
                }
                restingSection(round)
                upcomingSection(after: round)
            } else if tournament.allRoundsCompleted {
                allPlayedCard
            } else {
                EmptyStateView(symbol: "hourglass", title: "Preparing the next round", message: "Rounds are created from the standings when the previous round is complete.")
                    .cardStyle()
            }
        }
    }

    @ViewBuilder
    private func restingSection(_ round: Round) -> some View {
        let names = tournament.configuration.format.usesTeams
            ? round.restingTeamIDs.compactMap { tournament.team($0)?.name }
            : round.restingPlayerIDs.map { tournament.playerName($0) }
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Resting")
            if names.isEmpty {
                Text("No one rests this round")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.xs)
            } else {
                FlowRow(items: names) { PlayerChip(name: $0) }
            }
        }
    }

    @ViewBuilder
    private func upcomingSection(after round: Round) -> some View {
        if let next = tournament.rounds.first(where: { $0.number == round.number + 1 }) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader(title: String(localized: "Up next · \(tournament.roundTitle(next))"))
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(next.matches) { match in
                        HStack {
                            Text("Court \(match.court)")
                                .font(.padelMeta.weight(.semibold))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(width: 64, alignment: .leading)
                            Text("\(tournament.sideName(match.sideA))  vs  \(tournament.sideName(match.sideB))")
                                .font(.padelMeta)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(2)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .cardStyle(padding: Theme.Spacing.m)
            }
        } else if !tournament.configuration.format.hasPrecomputedSchedule || tournament.configuration.standingsBasedFinalRound,
                  round.number < tournament.configuration.totalRoundCount {
            Text("The next round is drawn from the standings when this round is complete.")
                .font(.padelMeta)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.xs)
        }
    }

    private var allPlayedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Label("All rounds played", systemImage: "flag.checkered")
                .font(.padelSection)
                .foregroundStyle(Theme.Colors.textPrimary)
            if let champion = tournament.playoffChampion {
                Label(String(localized: "Playoff winners: \(tournament.sideName(champion))"), systemImage: "trophy.fill")
                    .font(.padelName)
                    .foregroundStyle(Theme.Colors.accentText)
            }
            Text("Check the standings, then finish the tournament to lock the results.")
                .font(.padelMeta)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button("Finish Tournament") { confirmFinish = true }
                .buttonStyle(.padelPrimary)
                .accessibilityIdentifier("finishTournamentButton")
        }
        .cardStyle()
    }

    private var completedCard: some View {
        let standings = StandingsCalculator.compute(tournament)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Label("Tournament finished", systemImage: "trophy.fill")
                .font(.padelSection)
                .foregroundStyle(Theme.Colors.accentText)
            if let champion = tournament.playoffChampion {
                Text("Playoff winners: \(tournament.sideName(champion))")
                    .font(.padelName)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            ForEach(standings.entries.prefix(3)) { entry in
                HStack {
                    Text("\(entry.rank).")
                        .font(.padelName.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 28, alignment: .leading)
                    Text(entry.name).font(.padelName)
                    Spacer()
                    Text(tournament.configuration.scoring.isSets ? "\(entry.points) games" : "\(entry.points) pts").font(.padelName.monospacedDigit())
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityElement(children: .combine)
            }
        }
        .cardStyle()
    }
}

/// A court card: teams, score, state and the route into scoring.
struct MatchCard: View {
    let tournament: Tournament
    let match: Match
    let onOpen: () -> Void
    let onEnterResult: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text("Court \(match.court)")
                    .font(.padelSection)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                StatusBadge(kind: match.badge(rule: tournament.scoringRule(for: match)))
            }
            HStack(alignment: .center) {
                SideNamesView(names: tournament.sideNames(of: match, .a))
                Spacer(minLength: Theme.Spacing.s)
                if match.hasStarted {
                    Text(tournament.configuration.scoring.isSets ? match.resultText(rule: tournament.scoringRule(for: match)) : "\(match.score.a) – \(match.score.b)")
                        .font(.padelScore(size: tournament.configuration.scoring.isSets ? 18 : 28))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize()
                } else {
                    Text("vs")
                        .font(.padelMeta)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.s)
                SideNamesView(names: tournament.sideNames(of: match, .b), alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tournament.accessibilityDescription(of: match))

            if !match.isCompleted, let progress = match.progress(rule: tournament.scoringRule(for: match)), match.hasStarted {
                ProgressBar(value: progress)
            }

            HStack(spacing: Theme.Spacing.s) {
                Button(action: onOpen) {
                    Label(match.isCompleted ? "View Match" : (match.hasStarted ? "Open Score" : "Start Scoring"), systemImage: "scope")
                }
                .buttonStyle(.padelSecondary)
                .accessibilityIdentifier("openScore-court\(match.court)")
                if !match.isCompleted && tournament.status == .active {
                    Button(action: onEnterResult) {
                        Label("Result", systemImage: "number")
                    }
                    .buttonStyle(.padelSecondary)
                    .frame(maxWidth: 130)
                    .accessibilityHint("Enter the final score directly")
                    .accessibilityIdentifier("enterResult-court\(match.court)")
                }
            }
        }
        .cardStyle()
    }
}

/// Wrapping row of chips.
struct FlowRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: Theme.Spacing.s) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
