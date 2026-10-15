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
    @State private var invitation: Invitation?
    @State private var isPreparingInvitation = false
    @State private var confirmLeave = false
    @State private var liveBoard: LiveBoardLink?
    @State private var isPreparingLiveBoard = false

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
                    if tournament.sharing != nil || (AppModel.isStoreDemoShared && tournament.status == .active && tournament.currentRound != nil) {
                        SharedTournamentBanner(tournament: tournament, error: model.sharedSync.errors[tournament.id])
                    }
                    if tournament.openConflictCount > 0 && !tournament.isGuest {
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
        .task { await openDemoScreen() }
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
                    if tournament.isGuest {
                        Button(role: .destructive) {
                            confirmLeave = true
                        } label: {
                            Label("Leave Tournament", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        if tournament.status == .active {
                            Button {
                                Task { await prepareInvitation() }
                            } label: {
                                Label("Invite Players", systemImage: "person.badge.plus")
                            }
                            .disabled(isPreparingInvitation)
                            .accessibilityIdentifier("invitePlayersButton")
                        }
                        Button {
                            Task { await prepareLiveBoard() }
                        } label: {
                            Label("Share Live Leaderboard", systemImage: "tv")
                        }
                        .disabled(isPreparingLiveBoard)
                        Button {
                            showManage = true
                        } label: {
                            Label("Manage Tournament", systemImage: "slider.horizontal.3")
                        }
                        .accessibilityIdentifier("manageTournamentButton")
                    }
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
        .sheet(item: $invitation) { invitation in
            InvitationSheet(tournamentName: tournament.name, url: invitation.url) {
                self.invitation = nil
                Task {
                    do {
                        try await model.sharedSync.stopSharing(tournamentID)
                    } catch {
                        model.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            }
        }
        .sheet(item: $liveBoard) { link in
            LiveBoardSheet(tournamentName: tournament.name, url: link.url, error: model.liveBoards.errors[tournamentID]) {
                liveBoard = nil
                Task {
                    do {
                        try await model.liveBoards.stop(tournamentID)
                    } catch {
                        model.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            }
        }
        .confirmationDialog("Leave tournament?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave Tournament", role: .destructive) {
                Task {
                    do {
                        try await model.sharedSync.stopSharing(tournamentID)
                        path.removeAll()
                    } catch {
                        model.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The tournament is removed from this phone. The organiser keeps it.")
        }
        .overlay {
            if isPreparingInvitation {
                ProgressView("Preparing invitation…")
                    .padding(Theme.Spacing.l)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if isPreparingLiveBoard {
                ProgressView("Preparing live leaderboard…")
                    .padding(Theme.Spacing.l)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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

extension TournamentView {
    struct Invitation: Identifiable {
        let url: URL
        var id: URL { url }
    }

    struct LiveBoardLink: Identifiable {
        let url: URL
        var id: URL { url }
    }

    /// Screenshot run only: opens the tab or sheet asked for with `-demoScreen`.
    private func openDemoScreen() async {
        switch AppModel.demoScreen {
        case "schedule": tab = .schedule
        case "standings", "playoffs": tab = .standings
        case "invite":
            try? await Task.sleep(for: .milliseconds(500))
            await prepareInvitation()
        default: break
        }
    }

    /// Publishes the public spectator board (the first time) and shows its link.
    private func prepareLiveBoard() async {
        isPreparingLiveBoard = true
        defer { isPreparingLiveBoard = false }
        do {
            liveBoard = LiveBoardLink(url: try await model.liveBoards.start(tournamentID))
        } catch {
            model.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Shares the tournament through iCloud (the first time) and shows the link.
    private func prepareInvitation() async {
        if AppModel.isStoreDemo {
            invitation = Invitation(url: AppModel.storeDemoInvitationURL)
            return
        }
        isPreparingInvitation = true
        defer { isPreparingInvitation = false }
        do {
            invitation = Invitation(url: try await model.sharedSync.invitationURL(for: tournamentID))
            model.scheduleSharedSync()
        } catch {
            model.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Explains who keeps the schedule in a shared tournament, and shows sync problems.
struct SharedTournamentBanner: View {
    let tournament: Tournament
    let error: String?

    var body: some View {
        if let error {
            MessageBanner(style: .warning, message: error)
        } else if tournament.isGuest {
            MessageBanner(style: .info, message: String(localized: "Joined tournament. Points you score are sent to the organiser."))
        } else {
            MessageBanner(style: .info, message: String(localized: "Shared tournament. Everyone who joined can score; this phone keeps the schedule."))
        }
    }
}

/// The invitation link, ready to send, and a way to stop sharing.
struct InvitationSheet: View {
    let tournamentName: String
    let url: URL
    let onStopSharing: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Label("Invite Players", systemImage: "person.badge.plus")
                    .font(.padelSection)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Send this link to the players. Anyone with the link can join and score from their iPhone and Apple Watch.")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                ShareLink(item: url, subject: Text(tournamentName), message: Text("Join \(tournamentName) in PadelOS")) {
                    Label("Send Invitation", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.padelPrimary)
                Spacer()
                Button("Stop Sharing", role: .destructive, action: onStopSharing)
                    .frame(maxWidth: .infinity)
                Text("Players who joined keep their copy but no longer get updates.")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Spacing.l)
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// The public spectator link, ready to send or open on a TV, and a way to stop it.
struct LiveBoardSheet: View {
    let tournamentName: String
    let url: URL
    let error: String?
    let onStop: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Label("Live Leaderboard", systemImage: "tv")
                        .font(.padelSection)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Anyone with this link can follow the standings and courts live in a web browser, for example friends at the venue or a TV at the club.")
                        .font(.padelMeta)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if let error {
                        MessageBanner(style: .warning, message: String(localized: "The leaderboard could not be updated: \(error)"))
                    }
                    Text(url.absoluteString)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Theme.Colors.accentText)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .accessibilityIdentifier("liveBoardURL")
                    ShareLink(item: url, subject: Text(tournamentName), message: Text("Follow \(tournamentName) live")) {
                        Label("Send Link", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.padelPrimary)
                    Link(destination: url) {
                        Label("Open Page", systemImage: "safari")
                    }
                    .buttonStyle(.padelSecondary)
                    Button("Stop Live Leaderboard", role: .destructive, action: onStop)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.s)
                    Text("The page shows the tournament name, player names and scores. Stopping removes it from the web.")
                        .font(.padelMeta)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.Spacing.l)
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
            if !tournament.isGuest {
                Button("Finish Tournament") { confirmFinish = true }
                    .buttonStyle(.padelPrimary)
                    .accessibilityIdentifier("finishTournamentButton")
            }
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(.padelSecondary)
                .accessibilityIdentifier("openScore-court\(match.court)")
                if !match.isCompleted && tournament.status == .active {
                    Button(action: onEnterResult) {
                        Label("Result", systemImage: "number")
                            .lineLimit(1)
                    }
                    .buttonStyle(.padelSecondary)
                    .fixedSize(horizontal: true, vertical: false)
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
