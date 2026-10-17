import SwiftUI
import PadelCore
import PadelStore

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(TournamentStore.self) private var store
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Binding var path: [Route]
    @State private var creation: CreationRequest?

    /// Which flavour of the creation flow to open.
    struct CreationRequest: Identifiable {
        let id = UUID()
        var quickAmericano: Bool
    }

    var body: some View {
        let active = store.resumableTournament
        let others = store.recentTournaments.filter { $0.id != active?.id }
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                    .staggeredAppear(0)
                if !store.loadIssues.isEmpty {
                    MessageBanner(style: .warning, message: store.loadIssues.joined(separator: "\n"), onDismiss: { store.dismissLoadIssues() })
                }
                if let message = model.errorMessage {
                    MessageBanner(style: .error, message: message, onDismiss: { model.errorMessage = nil })
                }
                if let active {
                    Button {
                        path = [.tournament(active.id)]
                    } label: {
                        NowPlayingCard(tournament: active)
                    }
                    .buttonStyle(.pressable)
                    .zoomSource(active.id, in: zoomNamespace)
                    .accessibilityLabel(Text("Resume \(active.name)"))
                    .accessibilityValue(Text(verbatim: active.progressLabel))
                    .accessibilityIdentifier("resumeButton")
                    .staggeredAppear(1)
                }
                createButton
                    .staggeredAppear(2)
                quickStart
                    .staggeredAppear(3)
                if active == nil || !others.isEmpty {
                    recent(others)
                        .staggeredAppear(4)
                }
                playerStats
                    .staggeredAppear(5)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
            .animation(Motion.smooth, value: model.errorMessage)
        }
        .scrollIndicators(.hidden)
        .background { NightCourtBackground(style: .living) }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Screenshot run only (`-demoScreen create`).
            if AppModel.demoScreen == "create" && creation == nil {
                try? await Task.sleep(for: .milliseconds(300))
                creation = CreationRequest(quickAmericano: false)
            }
        }
        .fullScreenCover(item: $creation) { request in
            CreateTournamentFlow(quickAmericano: request.quickAmericano) { created in
                creation = nil
                path = [.tournament(created.id)]
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                BrandMark(animated: true)
                Spacer()
                Button {
                    path.append(.settings)
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.glassIcon)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("settingsButton")
            }
            Text("Play together.\nKeep score.")
                .font(.padelDisplay)
                .foregroundStyle(
                    LinearGradient(colors: [Theme.Colors.textPrimary, Theme.Colors.textPrimary, Theme.Colors.accentText], startPoint: .top, endPoint: .bottom)
                )
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, Theme.Spacing.s)
    }

    private var createButton: some View {
        Button {
            creation = CreationRequest(quickAmericano: false)
        } label: {
            Label("Create Tournament", systemImage: "plus")
                .font(.padelButton.weight(.heavy))
        }
        .buttonStyle(.padelPrimary)
        .accessibilityIdentifier("createTournamentButton")
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Quick start")
            Button {
                creation = CreationRequest(quickAmericano: true)
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "bolt.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.Colors.onAccent)
                        .frame(width: 46, height: 46)
                        .background(
                            LinearGradient(colors: [Theme.Colors.limeBright, Theme.Colors.limeDeep], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .shadow(color: Theme.Colors.accent.opacity(0.35), radius: 10, y: 4)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: TournamentFormat.americano.localizedName)
                            .font(.padelName.weight(.bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(verbatim: quickStartDetail)
                            .font(.padelMeta)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityHidden(true)
                }
                .surfaceCard(padding: Theme.Spacing.m)
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Starts a new Americano with your usual settings")
            .accessibilityIdentifier("quickStartButton")
        }
    }

    /// "8 recent players · 2 courts · 24 points", every part localized.
    private var quickStartDetail: String {
        let settings = model.settings.settings
        let recent = settings.recentPlayerNames.count
        let players = recent >= 4
            ? String(localized: "\(min(recent, settings.defaultCourtCount * 4)) recent players")
            : String(localized: "Add players")
        let courts = String(localized: "\(settings.defaultCourtCount) courts")
        let points = ScoringRule.totalPoints(settings.defaultPoints).localizedName
        return [players, courts, points].joined(separator: " · ")
    }

    private func recent(_ tournaments: [Tournament]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Recent tournaments")
            if store.recentTournaments.isEmpty {
                EmptyStateView(symbol: "sportscourt", title: "No tournaments yet", message: "Create one in under a minute. No account needed — everything stays on this iPhone.")
                    .surfaceCard(padding: 0)
            } else {
                VStack(spacing: Theme.Spacing.m) {
                    ForEach(Array(tournaments.enumerated()), id: \.element.id) { index, tournament in
                        Button {
                            path = [.tournament(tournament.id)]
                        } label: {
                            TournamentCard(tournament: tournament)
                        }
                        .buttonStyle(.pressable)
                        .zoomSource(tournament.id, in: zoomNamespace)
                        .scrollReveal()
                        .staggeredAppear(index + 5)
                    }
                }
            }
        }
    }

    /// Entry to the player leaderboard, once there is something to show: the current
    /// top three as stacked avatars.
    @ViewBuilder
    private var playerStats: some View {
        if !store.tournaments.isEmpty {
            let leaders = PlayerRecords.sorted(PlayerRecords.compute(store.tournaments), by: .wins).prefix(3)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Players")
                Button {
                    path.append(.players)
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        ZStack {
                            ForEach(Array(leaders.enumerated().reversed()), id: \.element.id) { index, record in
                                PlayerAvatar(name: record.name, size: 34, ring: index == 0 ? Theme.Colors.accent : nil)
                                    .overlay(Circle().strokeBorder(Theme.Colors.surface, lineWidth: index == 0 ? 0 : 2))
                                    .offset(x: CGFloat(index) * 16)
                            }
                            if leaders.isEmpty {
                                Image(systemName: "person.2.fill")
                                    .foregroundStyle(Theme.Colors.onAccent)
                                    .frame(width: 34, height: 34)
                                    .background(Theme.Colors.accent, in: Circle())
                            }
                        }
                        .frame(width: 66, alignment: .leading)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Player Stats")
                                .font(.padelName.weight(.bold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("Wins, form and partners across all your tournaments")
                                .font(.padelMeta)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .surfaceCard(padding: Theme.Spacing.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Opens the player leaderboard")
                .accessibilityIdentifier("playersButton")
            }
        }
    }
}

// MARK: - Now playing

/// The active tournament as a floodlit scoreboard: progress ring, round and a live
/// mini-scoreboard for every court. Always dark, like a real scoreboard.
struct NowPlayingCard: View {
    let tournament: Tournament

    var body: some View {
        let round = tournament.currentRound
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(spacing: 6) {
                        LiveDot(size: 7)
                        Text("Now playing")
                            .font(.padelEyebrow)
                            .tracking(1.1)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    Text(verbatim: tournament.name)
                        .font(.padelHeadline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Text(verbatim: "\(tournament.progressLabel) · \(tournament.configuration.format.localizedName)")
                        .font(.padelMeta.weight(.medium))
                        .foregroundStyle(Theme.Colors.onDarkSecondary)
                }
                Spacer(minLength: 0)
                ProgressRing(value: tournament.progressFraction, label: tournament.shortProgressLabel)
            }

            if let round, !round.matches.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.s), GridItem(.flexible(), spacing: Theme.Spacing.s)], spacing: Theme.Spacing.s) {
                    ForEach(round.matches.prefix(4)) { match in
                        MiniScoreboard(tournament: tournament, match: match)
                    }
                }
                if round.matches.count > 4 {
                    Text("+ \(round.matches.count - 4) more")
                        .font(.padelMeta)
                        .foregroundStyle(Theme.Colors.onDarkSecondary)
                }
            }

            HStack {
                Text("Resume")
                    .font(.padelButton.weight(.heavy))
                Spacer()
                Image(systemName: "arrow.forward")
                    .font(.body.weight(.heavy))
            }
            .foregroundStyle(Theme.Colors.ink)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(minHeight: 50)
            .background(
                LinearGradient(colors: [Theme.Colors.limeBright, Theme.Colors.accent], startPoint: .top, endPoint: .bottom),
                in: Capsule()
            )
        }
        .padding(Theme.Spacing.l)
        .background {
            ZStack {
                Theme.Colors.graphite
                RadialGradient(colors: [Theme.Colors.accent.opacity(0.28), .clear], center: .topTrailing, startRadius: 10, endRadius: 320)
                CourtLines()
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Theme.Colors.accent.opacity(0.55), Color.white.opacity(0.06)], startPoint: .topTrailing, endPoint: .bottomLeading), lineWidth: 1)
        )
        .shadow(color: Theme.Colors.accent.opacity(0.18), radius: 24, y: 10)
        .environment(\.colorScheme, .dark)
    }
}

/// Court number, score and state of one match, scoreboard style.
struct MiniScoreboard: View {
    let tournament: Tournament
    let match: Match

    var body: some View {
        let rule = tournament.scoringRule(for: match)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text("Court \(match.court)")
                    .font(.padelEyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.onDarkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if match.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.onDarkSecondary)
                } else if match.hasStarted {
                    LiveDot(size: 6)
                }
            }
            if match.hasStarted {
                Text(verbatim: rule.isSets ? match.resultText(rule: rule) : "\(match.score.a) – \(match.score.b)")
                    .font(.padelScoreboard(size: rule.isSets ? 18 : 26))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text("vs")
                    .font(.padelScoreboard(size: 22))
                    .foregroundStyle(Theme.Colors.onDarkSecondary)
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(match.status == .inProgress ? Theme.Colors.accent.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .animation(Motion.snappy, value: match.score)
    }
}

/// Circular progress with a short label inside ("R2/7").
struct ProgressRing: View {
    let value: Double
    let label: String
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, value)))
                .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.Colors.accent.opacity(0.6), radius: 4)
            Text(verbatim: label)
                .font(.system(size: 13, weight: .heavy).width(.condensed))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .padding(6)
        }
        .frame(width: size, height: size)
        .animation(Motion.smooth, value: value)
        .accessibilityHidden(true)
    }
}

// MARK: - Recent

/// A recent tournament: format glyph, name, summary and progress.
struct TournamentCard: View {
    let tournament: Tournament

    var body: some View {
        let finished = tournament.status == .completed
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            FormatGlyph(format: tournament.configuration.format, size: CGSize(width: 54, height: 38))
                .padding(.trailing, 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: tournament.name)
                        .font(.padelName.weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: Theme.Spacing.s)
                    Text(verbatim: finished ? String(localized: "Finished") : tournament.shortProgressLabel)
                        .font(.padelEyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(finished ? Theme.Colors.textSecondary : Theme.Colors.onAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(finished ? Theme.Colors.surfaceRaised : Theme.Colors.accent, in: Capsule())
                }
                Text(verbatim: tournament.summaryLine)
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
                ProgressBar(value: tournament.progressFraction, height: 4)
                    .accessibilityHidden(true)
            }
        }
        .surfaceCard(padding: Theme.Spacing.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the tournament")
    }
}

/// The two lime slashes and the wordmark. When `animated`, the slashes are drawn in.
struct BrandMark: View {
    var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        let visible = drawn || !animated || reduceMotion
        HStack(spacing: Theme.Spacing.s) {
            HStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Colors.accent)
                        .frame(width: 5, height: 20)
                        .scaleEffect(y: visible ? 1 : 0.05, anchor: .bottom)
                        .rotationEffect(.degrees(20))
                        .animation(Motion.bouncy.delay(0.1 + Double(index) * 0.1), value: drawn)
                }
            }
            .shadow(color: Theme.Colors.accent.opacity(0.5), radius: 6)
            Text("PADEL")
                .font(.system(.title3, design: .default, weight: .black).width(.expanded))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PadelOS")
        .onAppear { drawn = true }
    }
}
