import SwiftUI
import PadelCore
import PadelStore

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(TournamentStore.self) private var store
    @Binding var path: [Route]
    @State private var creation: CreationRequest?

    /// Which flavour of the creation flow to open.
    struct CreationRequest: Identifiable {
        let id = UUID()
        var quickAmericano: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                if !store.loadIssues.isEmpty {
                    MessageBanner(style: .warning, message: store.loadIssues.joined(separator: "\n"), onDismiss: { store.dismissLoadIssues() })
                }
                if let message = model.errorMessage {
                    MessageBanner(style: .error, message: message, onDismiss: { model.errorMessage = nil })
                }
                actions
                quickStart
                recent
                playerStats
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $creation) { request in
            CreateTournamentFlow(quickAmericano: request.quickAmericano) { created in
                creation = nil
                path = [.tournament(created.id)]
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack {
                BrandMark()
                Spacer()
                Button {
                    path.append(.settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("settingsButton")
            }
            Text("Play together.\nKeep score.")
                .font(.padelHero)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, Theme.Spacing.l)
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.m) {
            Button {
                creation = CreationRequest(quickAmericano: false)
            } label: {
                Label("Create Tournament", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.padelPrimary)
            .accessibilityIdentifier("createTournamentButton")

            if let active = store.resumableTournament {
                Button {
                    path = [.tournament(active.id)]
                } label: {
                    HStack {
                        Image(systemName: "play.circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Resume \(active.name)")
                                .lineLimit(1)
                            Text(active.progressLabel)
                                .font(.padelMeta)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .buttonStyle(.padelSecondary)
                .accessibilityIdentifier("resumeButton")
            }
        }
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Quick start")
            Button {
                creation = CreationRequest(quickAmericano: true)
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(Theme.Colors.onAccent)
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.accent, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Americano")
                            .font(.padelName)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(quickStartDetail)
                            .font(.padelMeta)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .cardStyle(padding: Theme.Spacing.m)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts a new Americano with your usual settings")
            .accessibilityIdentifier("quickStartButton")
        }
    }

    private var quickStartDetail: String {
        let settings = model.settings.settings
        let recent = settings.recentPlayerNames.count
        let players = recent >= 4 ? String(localized: "\(min(recent, settings.defaultCourtCount * 4)) recent players") : String(localized: "Add players")
        return "\(players) · \(settings.defaultCourtCount) courts · \(settings.defaultPoints) points"
    }

    @ViewBuilder
    private var recent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Recent tournaments")
            if store.recentTournaments.isEmpty {
                EmptyStateView(symbol: "sportscourt", title: "No tournaments yet", message: "Create one in under a minute. No account needed — everything stays on this iPhone.")
                    .cardStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(store.recentTournaments) { tournament in
                        Button {
                            path = [.tournament(tournament.id)]
                        } label: {
                            TournamentRow(tournament: tournament)
                        }
                        .buttonStyle(.plain)
                        if tournament.id != store.recentTournaments.last?.id {
                            Divider().overlay(Theme.Colors.separator).padding(.leading, Theme.Spacing.l)
                        }
                    }
                }
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            }
        }
    }

    /// Entry to the player leaderboard, once there is something to show.
    @ViewBuilder
    private var playerStats: some View {
        if !store.tournaments.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader(title: "Players")
                Button {
                    path.append(.players)
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "person.2.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Colors.onAccent)
                            .frame(width: 36, height: 36)
                            .background(Theme.Colors.accent, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Player Stats")
                                .font(.padelName)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("Wins, form and partners across all your tournaments")
                                .font(.padelMeta)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .cardStyle(padding: Theme.Spacing.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the player leaderboard")
                .accessibilityIdentifier("playersButton")
            }
        }
    }
}

struct TournamentRow: View {
    let tournament: Tournament

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tournament.name)
                    .font(.padelName)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(tournament.summaryLine)
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(tournament.status == .completed ? "Finished" : tournament.shortProgressLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tournament.status == .completed ? Theme.Colors.textSecondary : Theme.Colors.accentText)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.l)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the tournament")
    }
}

/// The two-stroke "court lines" mark used as the brand logo.
struct BrandMark: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            HStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Colors.accent)
                        .frame(width: 5, height: 20)
                        .rotationEffect(.degrees(20))
                }
            }
            Text("PADEL")
                .font(.system(.title3, design: .default).weight(.heavy))
                .tracking(1)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PadelOS")
    }
}

// MARK: - Player stats

/// Leaderboard of everybody who played in a tournament on this iPhone. Players are
/// recognised by name (see `PlayerRecords`).
struct PlayersView: View {
    @Environment(TournamentStore.self) private var store
    @Binding var path: [Route]
    @State private var order: PlayerRecordOrder = .wins
    @State private var query = ""

    var body: some View {
        let all = PlayerRecords.compute(store.tournaments)
        let shown = PlayerRecords.sorted(PlayerRecords.filter(all, query: query), by: order)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if all.isEmpty {
                    EmptyStateView(symbol: "person.2", title: "No player stats yet", message: "Finish a match and every player's results appear here, across all your tournaments.")
                        .cardStyle()
                } else {
                    Picker("Sort by", selection: $order) {
                        ForEach(PlayerRecordOrder.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("playersSortPicker")

                    if shown.isEmpty {
                        EmptyStateView(symbol: "magnifyingglass", title: "No players found", message: "Players are matched by name across tournaments, ignoring case and accents.")
                            .cardStyle()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { index, record in
                                if index > 0 {
                                    Divider().overlay(Theme.Colors.separator).padding(.leading, Theme.Spacing.l)
                                }
                                Button {
                                    path.append(.player(record.key))
                                } label: {
                                    PlayerLeaderboardRow(position: index + 1, record: record, order: order)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("playerRow-\(index + 1)")
                            }
                        }
                        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("playersLeaderboard")

                        Text("Players are matched by name across tournaments, ignoring case and accents.")
                            .font(.padelMeta)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Theme.Spacing.xs)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .screenBackground()
        .navigationTitle("Players")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Search players")
    }
}

struct PlayerLeaderboardRow: View {
    let position: Int
    let record: PlayerRecord
    let order: PlayerRecordOrder

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Text("\(position)")
                .font(.padelMeta.monospacedDigit().weight(.semibold))
                .foregroundStyle(position == 1 ? Theme.Colors.accentText : Theme.Colors.textSecondary)
                .frame(minWidth: 22, alignment: .leading)
            PlayerAvatar(name: record.name, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(record.name)
                        .font(.padelName)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    if record.tournamentWins > 0 {
                        Label {
                            Text(verbatim: "\(record.tournamentWins)")
                        } icon: {
                            Image(systemName: "trophy.fill")
                        }
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.Colors.onAccent)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .background(Theme.Colors.accent, in: Capsule())
                    }
                }
                Text(verbatim: "\(String(localized: "\(record.tournamentsPlayed) tournaments")) · \(record.wins)-\(record.draws)-\(record.losses)")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.s)
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: metric)
                    .font(.padelSection.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(order.title)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows the player's history")
    }

    private var metric: String {
        switch order {
        case .wins: "\(record.wins)"
        case .winRate: record.winRate.percentText
        case .matches: "\(record.matchesPlayed)"
        }
    }

    private var accessibilityText: String {
        var parts = [String(localized: "Position \(position)"), record.name]
        if record.tournamentWins > 0 { parts.append(String(localized: "\(record.tournamentWins) tournament wins")) }
        parts.append(String(localized: "\(record.tournamentsPlayed) tournaments"))
        parts.append(String(localized: "\(record.wins) wins, \(record.draws) draws, \(record.losses) losses"))
        parts.append(String(localized: "Win rate") + " " + record.winRate.percentText)
        return parts.joined(separator: ", ")
    }
}

/// One player's statistics and history across all tournaments on this iPhone.
struct PlayerDetailView: View {
    @Environment(TournamentStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let key: PlayerKey
    @Binding var path: [Route]

    var body: some View {
        Group {
            if let record = PlayerRecords.record(for: key, in: store.tournaments) {
                content(record)
            } else {
                EmptyStateView(symbol: "person.crop.circle.badge.questionmark", title: "Player not found", message: "It may have been deleted.")
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ record: PlayerRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header(record)
                tiles(record)
                if !record.form.isEmpty { form(record) }
                if record.bestPartner != nil || record.mostFrequentOpponent != nil { people(record) }
                history(record)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .navigationTitle(record.name)
    }

    private func header(_ record: PlayerRecord) -> some View {
        HStack(spacing: Theme.Spacing.l) {
            PlayerAvatar(name: record.name, size: 64)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(record.name)
                    .font(.padelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "\(record.tournamentsPlayed) tournaments"))
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("playerDetailHeader")
    }

    private func tiles(_ record: PlayerRecord) -> some View {
        let columns = [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 140), spacing: Theme.Spacing.m)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.m) {
            StatTile(symbol: "trophy.fill", title: String(localized: "Tournament wins"), value: "\(record.tournamentWins)", highlighted: record.tournamentWins > 0)
            StatTile(symbol: "medal.fill", title: String(localized: "Podiums"), value: "\(record.podiums)")
            StatTile(symbol: "percent", title: String(localized: "Win rate"), value: record.winRate.percentText)
            StatTile(symbol: "sportscourt.fill", title: String(localized: "Matches"), value: "\(record.matchesPlayed)")
            StatTile(
                symbol: "list.number",
                title: String(localized: "W-D-L"),
                value: "\(record.wins)-\(record.draws)-\(record.losses)",
                spokenValue: String(localized: "\(record.wins) wins, \(record.draws) draws, \(record.losses) losses")
            )
            if record.pointsFor + record.pointsAgainst > 0 || record.gamesFor + record.gamesAgainst == 0 {
                StatTile(
                    symbol: "plusminus",
                    title: String(localized: "Points"),
                    value: "\(record.pointsFor)–\(record.pointsAgainst)",
                    spokenValue: String(localized: "\(record.pointsFor) for, \(record.pointsAgainst) against")
                )
            }
            if record.gamesFor + record.gamesAgainst > 0 {
                StatTile(
                    symbol: "tennisball.fill",
                    title: String(localized: "Games"),
                    value: "\(record.gamesFor)–\(record.gamesAgainst)",
                    spokenValue: String(localized: "\(record.gamesFor) for, \(record.gamesAgainst) against")
                )
            }
        }
    }

    private func form(_ record: PlayerRecord) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Form")
            HStack(spacing: Theme.Spacing.s) {
                ForEach(Array(record.form.enumerated()), id: \.offset) { _, outcome in
                    FormChip(outcome: outcome)
                }
                Spacer(minLength: 0)
            }
            .cardStyle(padding: Theme.Spacing.m)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Form")
            .accessibilityValue(record.form.map(\.spokenName).joined(separator: ", "))
            .accessibilityIdentifier("playerForm")
        }
    }

    private func people(_ record: PlayerRecord) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Partners and opponents")
            VStack(spacing: 0) {
                if let partner = record.bestPartner {
                    relationRow(
                        title: String(localized: "Best partner"),
                        relation: partner,
                        detail: String(localized: "\(partner.wins) wins together"),
                        spokenDetail: String(localized: "\(partner.wins) wins together")
                    )
                }
                if record.bestPartner != nil && record.mostFrequentOpponent != nil {
                    Divider().overlay(Theme.Colors.separator).padding(.leading, Theme.Spacing.l)
                }
                if let rival = record.mostFrequentOpponent {
                    relationRow(
                        title: String(localized: "Most frequent opponent"),
                        relation: rival,
                        detail: String(localized: "\(rival.matches) matches") + " · \(rival.wins)-\(rival.draws)-\(rival.losses)",
                        spokenDetail: String(localized: "\(rival.matches) matches") + ", " + String(localized: "\(rival.wins) wins, \(rival.draws) draws, \(rival.losses) losses")
                    )
                }
            }
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        }
    }

    private func relationRow(title: String, relation: PlayerRelation, detail: String, spokenDetail: String) -> some View {
        Button {
            path.append(.player(relation.key))
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                PlayerAvatar(name: relation.name, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .textCase(.uppercase)
                        .font(.padelOverline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(relation.name)
                        .font(.padelName)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.padelMeta)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, relation.name, spokenDetail].joined(separator: ", "))
        .accessibilityHint("Shows the player's history")
        .accessibilityAddTraits(.isButton)
    }

    private func history(_ record: PlayerRecord) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "History")
            VStack(spacing: 0) {
                ForEach(Array(record.tournaments.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider().overlay(Theme.Colors.separator).padding(.leading, Theme.Spacing.l)
                    }
                    Button {
                        path.append(.tournament(entry.tournamentID))
                    } label: {
                        PlayerHistoryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("playerHistory")
        }
    }
}

/// A big number with a caption, for the player screen.
struct StatTile: View {
    let symbol: String
    let title: String
    let value: String
    var highlighted = false
    var spokenValue: String?
    @ScaledMetric(relativeTo: .title) private var valueSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(highlighted ? Theme.Colors.onAccent : Theme.Colors.accentText)
                .frame(width: 30, height: 30)
                .background(highlighted ? Theme.Colors.accent : Theme.Colors.surfaceRaised, in: Circle())
                .accessibilityHidden(true)
            Text(verbatim: value)
                .font(.padelScore(size: valueSize))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title)
                .font(.padelMeta)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle(padding: Theme.Spacing.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spokenValue ?? value)
    }
}

/// W / D / L chip in a player's form line.
struct FormChip: View {
    let outcome: MatchOutcome
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 40

    var body: some View {
        Text(outcome.letter)
            .font(.padelSection)
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background, in: Circle())
            .overlay(Circle().strokeBorder(outcome == .loss ? Theme.Colors.danger : Color.clear, lineWidth: 1.5))
    }

    private var foreground: Color {
        switch outcome {
        case .win: Theme.Colors.onAccent
        case .draw: Theme.Colors.textPrimary
        case .loss: Theme.Colors.danger
        }
    }

    private var background: Color {
        switch outcome {
        case .win: Theme.Colors.accent
        case .draw: Theme.Colors.surfaceRaised
        case .loss: Theme.Colors.surface
        }
    }
}

/// One tournament in a player's history.
struct PlayerHistoryRow: View {
    let entry: PlayerTournamentRecord

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle().fill(entry.isWin ? Theme.Colors.accent : Theme.Colors.surfaceRaised)
                if entry.isWin {
                    Image(systemName: "trophy.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.Colors.onAccent)
                } else {
                    Text(verbatim: rankText)
                        .font(.padelMeta.monospacedDigit().weight(.bold))
                        .foregroundStyle(entry.isPodium ? Theme.Colors.accentText : Theme.Colors.textSecondary)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.tournamentName)
                    .font(.padelName)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(verbatim: "\(entry.date.formatted(date: .abbreviated, time: .omitted)) · \(entry.format.localizedName)")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                Text(verbatim: resultLine)
                    .font(.padelMeta.monospacedDigit())
                    .foregroundStyle(entry.isCompleted ? Theme.Colors.textSecondary : Theme.Colors.accentText)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.s)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.l)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the tournament")
        .accessibilityAddTraits(.isButton)
    }

    private var rankText: String {
        guard let rank = entry.rank else { return "–" }
        return entry.isTied ? "=\(rank)" : "\(rank)"
    }

    private var resultLine: String {
        var line = String(localized: "W-D-L") + " \(entry.wins)-\(entry.draws)-\(entry.losses)"
        if !entry.isCompleted { line += " · " + String(localized: "In progress") }
        return line
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let rank = entry.rank {
            parts.append(entry.isTied ? String(localized: "Shared position \(rank)") : String(localized: "Position \(rank)"))
        }
        if entry.isWin { parts.append(String(localized: "Won the tournament")) }
        parts.append(entry.tournamentName)
        parts.append(entry.date.formatted(date: .abbreviated, time: .omitted))
        parts.append(entry.format.localizedName)
        parts.append(String(localized: "\(entry.wins) wins, \(entry.draws) draws, \(entry.losses) losses"))
        if !entry.isCompleted { parts.append(String(localized: "In progress")) }
        return parts.joined(separator: ", ")
    }
}

extension PlayerRecordOrder {
    var title: String {
        switch self {
        case .wins: String(localized: "Wins")
        case .winRate: String(localized: "Win rate")
        case .matches: String(localized: "Matches")
        }
    }
}

extension MatchOutcome {
    /// One letter for the form line (the same letters as the standings columns).
    var letter: String {
        switch self {
        case .win: String(localized: "W")
        case .draw: String(localized: "D")
        case .loss: String(localized: "L")
        }
    }

    var spokenName: String {
        switch self {
        case .win: String(localized: "Won")
        case .draw: String(localized: "Draw")
        case .loss: String(localized: "Lost")
        }
    }
}

extension Optional where Wrapped == Double {
    /// "67 %" in the user's locale; a dash before the first match.
    var percentText: String {
        guard let value = self else { return "–" }
        return value.formatted(.percent.precision(.fractionLength(0)))
    }
}
