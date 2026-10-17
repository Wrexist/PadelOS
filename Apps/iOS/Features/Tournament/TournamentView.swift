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
    @Environment(SettingsStore.self) private var settings
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
    @State private var celebration = 0
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
        .background { NightCourtBackground(style: .living) }
    }

    @ViewBuilder
    private func content(_ tournament: Tournament) -> some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab.animation(Motion.smooth.motionSafe)) {
                ForEach(Tab.allCases) { Text(verbatim: $0.title).tag($0) }
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
                    Group {
                        switch tab {
                        case .live: LiveTab(tournament: tournament, path: $path, resultEntry: $resultEntry, confirmFinish: $confirmFinish)
                        case .schedule: ScheduleTab(tournament: tournament, path: $path, resultEntry: $resultEntry)
                        case .standings: StandingsTab(tournament: tournament)
                        }
                    }
                    .id(tab)
                    .transition(.opacity.combined(with: .offset(y: 12)))
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xxl)
                .animation(Motion.smooth, value: model.errorMessage)
            }
            .scrollIndicators(.hidden)
        }
        .overlay { ConfettiBurst(trigger: celebration).ignoresSafeArea() }
        .task {
            // A finished tournament greets you with confetti once the push has settled.
            try? await Task.sleep(for: .milliseconds(450))
            if store.tournament(tournamentID)?.status == .completed { celebration += 1 }
        }
        .sensoryFeedback(.success, trigger: tournament.completedRoundCount) { old, new in
            settings.settings.hapticsEnabled && new > old
        }
        .onChange(of: tournament.completedRoundCount) { old, new in
            guard new > old else { return }
            celebration += 1
            if tournament.status != .completed {
                model.showToast(String(localized: "Round complete"))
            }
        }
        .onChange(of: tournament.status) { old, new in
            if old != .completed && new == .completed { celebration += 1 }
        }
        .navigationTitle(Text(verbatim: tournament.name))
        .navigationBarTitleDisplayMode(.inline)
        .task { await openDemoScreen() }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(verbatim: tournament.name)
                        .font(.headline.width(.expanded))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(verbatim: tournament.summaryLine)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                menu(tournament)
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
                    .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else if isPreparingLiveBoard {
                ProgressView("Preparing live leaderboard…")
                    .padding(Theme.Spacing.l)
                    .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(Motion.snappy, value: isPreparingInvitation)
        .animation(Motion.snappy, value: isPreparingLiveBoard)
        .sheet(isPresented: $showConflicts) {
            ConflictsView(tournamentID: tournamentID)
        }
        .sheet(item: Binding(get: { resultEntry.map { IdentifiedMatch(id: $0) } }, set: { resultEntry = $0?.id })) { item in
            ResultEntrySheet(tournamentID: tournamentID, matchID: item.id)
        }
        .confirmationDialog("Finish tournament?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish Tournament") {
                model.run { try store.perform(tournamentID) { (t, c) throws(TournamentError) in t.finish(now: c.now) } }
                withAnimation(Motion.smooth.motionSafe) { tab = .standings }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Final standings are locked. You can reopen the tournament later.")
        }
    }

    private func menu(_ tournament: Tournament) -> some View {
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
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("tournamentMenu")
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
        case "leaderboard":
            try? await Task.sleep(for: .milliseconds(500))
            liveBoard = LiveBoardLink(url: AppModel.storeDemoLiveBoardURL)
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
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "person.badge.plus")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.Colors.onAccent)
                        .frame(width: 52, height: 52)
                        .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Invite Players")
                        .font(.padelHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                Text("Send this link to the players. Anyone with the link can join and score from their iPhone and Apple Watch.")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ShareLink(item: url, subject: Text(verbatim: tournamentName), message: Text("Join \(tournamentName) in PadelOS")) {
                    Label("Send Invitation", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.padelPrimary)
                Spacer()
                Button("Stop Sharing", role: .destructive, action: onStopSharing)
                    .buttonStyle(.padelDestructive)
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
        .presentationDetents([.medium, .large])
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
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "tv")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.Colors.onAccent)
                            .frame(width: 52, height: 52)
                            .background(
                                LinearGradient(colors: [Theme.Colors.limeBright, Theme.Colors.limeDeep], startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .shadow(color: Theme.Colors.accent.opacity(0.4), radius: 10)
                            .accessibilityHidden(true)
                        Text("Live Leaderboard")
                            .font(.padelHeadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Text("Anyone with this link can follow the standings and courts live in a web browser, for example friends at the venue or a TV at the club.")
                        .font(.padelMeta)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error {
                        MessageBanner(style: .warning, message: String(localized: "The leaderboard could not be updated: \(error)"))
                    }
                    // The link as a little scoreboard: live dot, tournament, address.
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        HStack(spacing: 6) {
                            LiveDot(size: 7)
                            Text(verbatim: tournamentName)
                                .font(.padelEyebrow)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.Colors.accent)
                                .lineLimit(1)
                        }
                        Text(verbatim: url.absoluteString)
                            .font(.footnote.monospaced().weight(.semibold))
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .accessibilityIdentifier("liveBoardURL")
                    }
                    .padding(Theme.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        ZStack {
                            Theme.Colors.graphite
                            RadialGradient(colors: [Theme.Colors.accent.opacity(0.22), .clear], center: .topTrailing, startRadius: 4, endRadius: 220)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                    .environment(\.colorScheme, .dark)
                    ShareLink(item: url, subject: Text(verbatim: tournamentName), message: Text("Follow \(tournamentName) live")) {
                        Label("Send Link", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.padelPrimary)
                    Link(destination: url) {
                        Label("Open Page", systemImage: "safari")
                    }
                    .buttonStyle(.padelSecondary)
                    Button("Stop Live Leaderboard", role: .destructive, action: onStop)
                        .buttonStyle(.padelDestructive)
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

// MARK: - Round header

/// The round as a headline plus a track of every planned round: played rounds lit, the
/// current one filling up as its matches finish.
struct RoundHeader: View {
    let tournament: Tournament

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(verbatim: tournament.progressLabel)
                    .font(.padelHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
                if let round = tournament.currentRound, round.kind == .final || round.kind == .knockout {
                    Text(round.kind == .knockout ? "PLAYOFFS" : "FINAL")
                        .font(.padelEyebrow)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, 3)
                        .foregroundStyle(Theme.Colors.onAccent)
                        .background(Theme.Colors.accent, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            RoundTrack(tournament: tournament)
        }
        .padding(.top, Theme.Spacing.s)
        .animation(Motion.bouncy, value: tournament.currentRoundNumber)
    }
}

/// One segment per planned round. Knockout rounds are taller.
struct RoundTrack: View {
    let tournament: Tournament

    var body: some View {
        let total = max(1, tournament.configuration.totalRoundCount)
        HStack(alignment: .center, spacing: total > 12 ? 3 : 5) {
            ForEach(1...total, id: \.self) { number in
                segment(number)
            }
        }
        .frame(height: 12)
        .animation(Motion.smooth, value: tournament.progressFraction)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((tournament.progressFraction * 100).rounded())) percent")
    }

    private func segment(_ number: Int) -> some View {
        let round = tournament.rounds.first { $0.number == number }
        let isKnockout = number > tournament.configuration.roundCount
        let done = round?.isCompleted ?? false
        let isCurrent = tournament.currentRoundNumber == number
        let fraction: Double = {
            guard let round, !round.matches.isEmpty else { return 0 }
            return Double(round.matches.filter(\.isCompleted).count) / Double(round.matches.count)
        }()
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.surfaceRaised)
                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(width: proxy.size.width * (done ? 1 : (isCurrent ? max(0.12, fraction) : 0)))
                    .shadow(color: Theme.Colors.accent.opacity(isCurrent ? 0.6 : 0), radius: 4)
            }
        }
        .frame(height: isKnockout ? 12 : 6)
        .overlay {
            if isCurrent {
                Capsule().strokeBorder(Theme.Colors.accentText.opacity(0.7), lineWidth: 1)
            }
        }
    }
}

// MARK: - Live

struct LiveTab: View {
    @Environment(AppModel.self) private var model
    let tournament: Tournament
    @Binding var path: [Route]
    @Binding var resultEntry: MatchID?
    @Binding var confirmFinish: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            RoundHeader(tournament: tournament)

            if tournament.status == .completed {
                FinishedCard(tournament: tournament)
            } else if let round = tournament.currentRound {
                VStack(spacing: Theme.Spacing.m) {
                    ForEach(Array(round.matches.enumerated()), id: \.element.id) { index, match in
                        CourtTile(tournament: tournament, match: match, onOpen: {
                            path.append(.match(tournament.id, match.id))
                        }, onEnterResult: {
                            resultEntry = match.id
                        })
                        .dealIn(index)
                    }
                }
                restingSection(round)
                upcomingSection(after: round)
            } else if tournament.allRoundsCompleted {
                allPlayedCard
            } else {
                EmptyStateView(symbol: "hourglass", title: "Preparing the next round", message: "Rounds are created from the standings when the previous round is complete.")
                    .surfaceCard(padding: 0)
            }
        }
    }

    @ViewBuilder
    private func restingSection(_ round: Round) -> some View {
        let names = tournament.configuration.format.usesTeams
            ? round.restingTeamIDs.compactMap { tournament.team($0)?.name }
            : round.restingPlayerIDs.map { tournament.playerName($0) }
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Resting")
            if names.isEmpty {
                Text("No one rests this round")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.xs)
            } else {
                FlowRow(items: names) { name in
                    PlayerChip(name: name)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
        }
    }

    @ViewBuilder
    private func upcomingSection(after round: Round) -> some View {
        if let next = tournament.rounds.first(where: { $0.number == round.number + 1 }) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader(verbatim: String(localized: "Up next · \(tournament.roundTitle(next))"))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(next.matches) { match in
                        HStack(spacing: Theme.Spacing.m) {
                            Text("Court \(match.court)")
                                .font(.padelEyebrow)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.Colors.accentText)
                                .frame(minWidth: 64, alignment: .leading)
                            Text("\(tournament.sideName(match.sideA))  vs  \(tournament.sideName(match.sideB))")
                                .font(.padelMeta)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, Theme.Spacing.s)
                        .accessibilityElement(children: .combine)
                        if match.id != next.matches.last?.id {
                            Divider().overlay(Theme.Colors.separator)
                        }
                    }
                }
                .surfaceCard(padding: Theme.Spacing.m)
            }
        } else if !tournament.configuration.format.hasPrecomputedSchedule || tournament.configuration.standingsBasedFinalRound,
                  round.number < tournament.configuration.totalRoundCount {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(Theme.Colors.accentText)
                    .accessibilityHidden(true)
                Text("The next round is drawn from the standings when this round is complete.")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.xs)
        }
    }

    private var allPlayedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Image(systemName: "flag.checkered")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.Colors.accentText)
                .symbolEffect(.bounce, value: tournament.completedRoundCount)
                .accessibilityHidden(true)
            Text("All rounds played")
                .font(.padelHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let champion = tournament.playoffChampion {
                Label(String(localized: "Playoff winners: \(tournament.sideName(champion))"), systemImage: "trophy.fill")
                    .font(.padelName.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accentText)
            }
            Text("Check the standings, then finish the tournament to lock the results.")
                .font(.padelMeta)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !tournament.isGuest {
                Button("Finish Tournament") { confirmFinish = true }
                    .buttonStyle(.padelPrimary)
                    .accessibilityIdentifier("finishTournamentButton")
            }
        }
        .surfaceCard(highlight: Theme.Colors.accent.opacity(0.5))
        .staggeredAppear(0)
    }
}

/// The finished tournament: trophy, champions and the podium.
struct FinishedCard: View {
    let tournament: Tournament
    @State private var celebration = 0

    var body: some View {
        let standings = StandingsCalculator.compute(tournament)
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "trophy.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.Colors.onAccent)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(colors: [Theme.Colors.limeBright, Theme.Colors.limeDeep], startPoint: .top, endPoint: .bottom),
                        in: Circle()
                    )
                    .shadow(color: Theme.Colors.accent.opacity(0.5), radius: 12)
                    .symbolEffect(.bounce, value: celebration)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tournament finished")
                        .font(.padelHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if let champion = tournament.playoffChampion {
                        Text("Playoff winners: \(tournament.sideName(champion))")
                            .font(.padelMeta.weight(.semibold))
                            .foregroundStyle(Theme.Colors.accentText)
                    }
                }
            }
            if standings.completedMatches > 0 {
                Podium(entries: Array(standings.entries.prefix(3)), unit: tournament.configuration.scoring.unitName)
            }
        }
        .surfaceCard(highlight: Theme.Colors.accent.opacity(0.45))
        .onAppear { celebration += 1 }
    }
}

// MARK: - Court tile

/// A court as a scoreboard tile: both teams with their score, a live progress line and
/// the way into scoring. Entering a result directly sits on its own pill in the header.
struct CourtTile: View {
    let tournament: Tournament
    let match: Match
    let onOpen: () -> Void
    let onEnterResult: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let rule = tournament.scoringRule(for: match)
        let winner = match.isCompleted ? ScoringEngine.winner(of: match) : nil
        let live = match.status == .inProgress
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Text("Court \(match.court)")
                    .font(.title3.weight(.heavy).width(.expanded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                    .layoutPriority(2)
                StatusBadge(kind: match.badge(rule: rule))
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if canEnterResult {
                    resultButton
                }
            }
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    VStack(spacing: Theme.Spacing.s) {
                        teamRow(.a, rule: rule, winner: winner)
                        if match.hasStarted, !match.isCompleted, let progress = match.progress(rule: rule) {
                            ProgressBar(value: progress, height: 3)
                                .accessibilityHidden(true)
                        } else {
                            HStack(spacing: Theme.Spacing.s) {
                                Rectangle().fill(Theme.Colors.separator).frame(height: 1)
                                if !match.hasStarted {
                                    Text("vs")
                                        .font(.padelEyebrow)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                                Rectangle().fill(Theme.Colors.separator).frame(height: 1)
                            }
                        }
                        teamRow(.b, rule: rule, winner: winner)
                    }
                    HStack(spacing: Theme.Spacing.s) {
                        if rule.isSets, match.hasStarted {
                            Text(verbatim: match.resultText(rule: rule))
                                .font(.padelMeta.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Label(match.isCompleted ? "View Match" : (match.hasStarted ? "Open Score" : "Start Scoring"), systemImage: "scope")
                            .font(.padelMeta.weight(.bold))
                            .foregroundStyle(Theme.Colors.accentText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "arrow.forward")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Theme.Colors.accentText)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text(verbatim: tournament.accessibilityDescription(of: match)))
            .accessibilityIdentifier("openScore-court\(match.court)")
        }
        .surfaceCard(highlight: live ? Theme.Colors.accent.opacity(0.55) : nil)
        .animation(Motion.snappy, value: match.score)
        .animation(Motion.smooth, value: match.status)
    }

    private var resultButton: some View {
        Button(action: onEnterResult) {
            // Long translations ("A CONTINUACIÓN") leave no room for the word: show the
            // symbol alone rather than a truncated label.
            ViewThatFits(in: .horizontal) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Label("Result", systemImage: "number")
                        .fixedSize()
                }
                Image(systemName: "number")
            }
            .font(.padelMeta.weight(.bold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minWidth: Theme.minimumTapTarget, minHeight: 36)
            .background(Theme.Colors.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Colors.separator, lineWidth: 1))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Result")
        .accessibilityHint("Enter the final score directly")
        .accessibilityIdentifier("enterResult-court\(match.court)")
    }

    private var canEnterResult: Bool {
        !match.isCompleted && tournament.status == .active
    }

    private func teamRow(_ side: TeamSide, rule: ScoringRule, winner: TeamSide?) -> some View {
        let names = tournament.sideNames(of: match, side)
        let other = side.opposite
        let leading = match.hasStarted && scoreValue(side, rule: rule) > scoreValue(other, rule: rule)
        return HStack(spacing: Theme.Spacing.m) {
            AvatarStack(names: names)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    Text(verbatim: name)
                        .font(winner == side ? .padelName.weight(.heavy) : .padelName.weight(.medium))
                        .foregroundStyle(winner == nil || winner == side ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: Theme.Spacing.s)
            if winner == side {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.Colors.accentText)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
            if match.hasStarted {
                Text("\(scoreValue(side, rule: rule))")
                    .font(.padelScoreboard(size: 40))
                    .foregroundStyle(leading || winner == side ? Theme.Colors.accentText : Theme.Colors.textPrimary)
                    .contentTransition(.numericText(value: Double(scoreValue(side, rule: rule))))
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
    }

    /// Points, or for games and sets the games of the set in play (sets won once decided).
    private func scoreValue(_ side: TeamSide, rule: ScoringRule) -> Int {
        guard rule.isSets else { return match.score[side] }
        guard let sets = match.sets else { return 0 }
        return sets.isDecided ? sets.setsWon[side] : sets.games[side]
    }
}

/// Overlapping avatars of one side.
struct AvatarStack: View {
    let names: [String]
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -size * 0.35) {
            ForEach(Array(names.prefix(2).enumerated()), id: \.offset) { _, name in
                PlayerAvatar(name: name, size: size)
                    .overlay(Circle().strokeBorder(Theme.Colors.surface, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
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
