import SwiftUI
import PadelCore
import PadelStore

// MARK: - Leaderboard

/// Leaderboard of everybody who played in a tournament on this iPhone: the top three on
/// a podium, then everyone as scoreboard rows that slide to their new place when the
/// order changes. Players are recognised by name (see `PlayerRecords`).
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
                        .surfaceCard(padding: 0)
                } else {
                    Picker("Sort by", selection: $order.animation(Motion.smooth.motionSafe)) {
                        ForEach(PlayerRecordOrder.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("playersSortPicker")

                    if shown.isEmpty {
                        EmptyStateView(symbol: "magnifyingglass", title: "No players found", message: "Players are matched by name across tournaments, ignoring case and accents.")
                            .surfaceCard(padding: 0)
                    } else {
                        if query.isEmpty && shown.count >= 3 {
                            Podium(items: shown.prefix(3).enumerated().map { index, record in
                                PodiumItem(
                                    id: record.key.rawValue,
                                    name: record.name,
                                    value: PlayerLeaderboardRow.metric(record, order: order),
                                    numeric: order == .winRate ? nil : Double(PlayerLeaderboardRow.metricValue(record, order: order)),
                                    rankLabel: (index + 1).formatted(),
                                    accessibilityLabel: PlayerLeaderboardRow.accessibilityText(record, position: index + 1)
                                )
                            })
                            .id(order)
                            .padding(.top, Theme.Spacing.s)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { index, record in
                                if index > 0 {
                                    Divider().overlay(Theme.Colors.separator).padding(.leading, 72)
                                }
                                Button {
                                    path.append(.player(record.key))
                                } label: {
                                    PlayerLeaderboardRow(position: index + 1, record: record, order: order)
                                }
                                .buttonStyle(.pressable)
                                .accessibilityIdentifier("playerRow-\(index + 1)")
                            }
                        }
                        .surfaceCard(padding: 0, cornerRadius: 22)
                        .animation(Motion.smooth, value: shown.map(\.id))
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
        .scrollIndicators(.hidden)
        .screenBackground(.living)
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
        let leader = position == 1
        HStack(spacing: Theme.Spacing.m) {
            Text("\(position)")
                .font(.padelScoreboard(size: 18))
                .foregroundStyle(leader ? Theme.Colors.accentText : Theme.Colors.textSecondary)
                .contentTransition(.numericText(value: Double(position)))
                .frame(minWidth: 22, alignment: .leading)
            PlayerAvatar(name: record.name, size: 38, ring: leader ? Theme.Colors.accent : nil)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(verbatim: record.name)
                        .font(.padelName.weight(leader ? .heavy : .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    if record.tournamentWins > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "trophy.fill")
                            Text(verbatim: record.tournamentWins.formatted())
                        }
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Theme.Colors.onAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
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
                Text(verbatim: Self.metric(record, order: order))
                    .font(.padelScoreboard(size: 24))
                    .foregroundStyle(leader ? Theme.Colors.accentText : Theme.Colors.textPrimary)
                    .contentTransition(.numericText())
                Text(verbatim: order.title)
                    .font(.padelEyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.m)
        .background(alignment: .leading) {
            if leader {
                LinearGradient(colors: [Theme.Colors.accent.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.accessibilityText(record, position: position)))
        .accessibilityHint("Shows the player's history")
    }

    static func metricValue(_ record: PlayerRecord, order: PlayerRecordOrder) -> Int {
        switch order {
        case .wins: record.wins
        case .winRate: Int(((record.winRate ?? 0) * 100).rounded())
        case .matches: record.matchesPlayed
        }
    }

    static func metric(_ record: PlayerRecord, order: PlayerRecordOrder) -> String {
        switch order {
        case .wins: record.wins.formatted()
        case .winRate: record.winRate.percentText
        case .matches: record.matchesPlayed.formatted()
        }
    }

    static func accessibilityText(_ record: PlayerRecord, position: Int) -> String {
        var parts = [String(localized: "Position \(position)"), record.name]
        if record.tournamentWins > 0 { parts.append(String(localized: "\(record.tournamentWins) tournament wins")) }
        parts.append(String(localized: "\(record.tournamentsPlayed) tournaments"))
        parts.append(String(localized: "\(record.wins) wins, \(record.draws) draws, \(record.losses) losses"))
        parts.append(String(localized: "Win rate") + " " + record.winRate.percentText)
        return parts.joined(separator: ", ")
    }
}

// MARK: - Player

/// One player's statistics and history across all tournaments on this iPhone: a
/// scoreboard header with the win rate as a ring, stat tiles, recent form, partners and
/// every tournament they played.
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
        .screenBackground(.living)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ record: PlayerRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header(record)
                    .staggeredAppear(0)
                tiles(record)
                    .staggeredAppear(1)
                if !record.form.isEmpty {
                    form(record)
                        .staggeredAppear(2)
                }
                if record.bestPartner != nil || record.mostFrequentOpponent != nil {
                    people(record)
                        .staggeredAppear(3)
                }
                history(record)
                    .staggeredAppear(4)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(Text(verbatim: record.name))
    }

    /// Always dark, like the Now Playing card on Home.
    private func header(_ record: PlayerRecord) -> some View {
        HStack(spacing: Theme.Spacing.l) {
            PlayerAvatar(name: record.name, size: 68, ring: Theme.Colors.accent)
                .shadow(color: Theme.Colors.accent.opacity(0.4), radius: 14)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(verbatim: record.name)
                    .font(.padelHeadline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(String(localized: "\(record.tournamentsPlayed) tournaments"))
                    .font(.padelMeta.weight(.medium))
                    .foregroundStyle(Theme.Colors.onDarkSecondary)
                if record.tournamentWins > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                        Text(String(localized: "\(record.tournamentWins) tournament wins"))
                    }
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Theme.Colors.ink)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, 4)
                    .background(Theme.Colors.accent, in: Capsule())
                }
            }
            Spacer(minLength: 0)
            ProgressRing(value: record.winRate ?? 0, label: record.winRate.percentText, size: 64)
        }
        .padding(Theme.Spacing.l)
        .background {
            ZStack {
                Theme.Colors.graphite
                RadialGradient(colors: [Theme.Colors.accent.opacity(0.26), .clear], center: .topTrailing, startRadius: 8, endRadius: 300)
                CourtLines()
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Theme.Colors.accent.opacity(0.5), Color.white.opacity(0.06)], startPoint: .topTrailing, endPoint: .bottomLeading), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("playerDetailHeader")
    }

    private func tiles(_ record: PlayerRecord) -> some View {
        let columns = [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 140), spacing: Theme.Spacing.m)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.m) {
            StatTile(symbol: "trophy.fill", title: String(localized: "Tournament wins"), value: record.tournamentWins.formatted(), highlighted: record.tournamentWins > 0)
            StatTile(symbol: "medal.fill", title: String(localized: "Podiums"), value: record.podiums.formatted())
            StatTile(symbol: "percent", title: String(localized: "Win rate"), value: record.winRate.percentText)
            StatTile(symbol: "sportscourt.fill", title: String(localized: "Matches"), value: record.matchesPlayed.formatted())
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
            SectionHeader("Form")
            HStack(spacing: Theme.Spacing.s) {
                ForEach(Array(record.form.enumerated()), id: \.offset) { index, outcome in
                    FormChip(outcome: outcome)
                        .staggeredAppear(index, distance: 10)
                }
                Spacer(minLength: 0)
            }
            .surfaceCard(padding: Theme.Spacing.m)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Form")
            .accessibilityValue(Text(verbatim: record.form.map(\.spokenName).joined(separator: ", ")))
            .accessibilityIdentifier("playerForm")
        }
    }

    private func people(_ record: PlayerRecord) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Partners and opponents")
            VStack(spacing: 0) {
                if let partner = record.bestPartner {
                    relationRow(
                        title: String(localized: "Best partner"),
                        symbol: "person.2.fill",
                        relation: partner,
                        detail: String(localized: "\(partner.wins) wins together"),
                        spokenDetail: String(localized: "\(partner.wins) wins together")
                    )
                }
                if record.bestPartner != nil && record.mostFrequentOpponent != nil {
                    Divider().overlay(Theme.Colors.separator).padding(.leading, 72)
                }
                if let rival = record.mostFrequentOpponent {
                    relationRow(
                        title: String(localized: "Most frequent opponent"),
                        symbol: "bolt.fill",
                        relation: rival,
                        detail: String(localized: "\(rival.matches) matches") + " · \(rival.wins)-\(rival.draws)-\(rival.losses)",
                        spokenDetail: String(localized: "\(rival.matches) matches") + ", " + String(localized: "\(rival.wins) wins, \(rival.draws) draws, \(rival.losses) losses")
                    )
                }
            }
            .surfaceCard(padding: 0, cornerRadius: 22)
        }
    }

    private func relationRow(title: String, symbol: String, relation: PlayerRelation, detail: String, spokenDetail: String) -> some View {
        Button {
            path.append(.player(relation.key))
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                PlayerAvatar(name: relation.name, size: 44)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: symbol)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Theme.Colors.onAccent)
                            .frame(width: 18, height: 18)
                            .background(Theme.Colors.accent, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.Colors.surface, lineWidth: 2))
                            .offset(x: 4, y: 4)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.padelEyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(verbatim: relation.name)
                        .font(.padelName.weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(verbatim: detail)
                        .font(.padelMeta)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(verbatim: [title, relation.name, spokenDetail].joined(separator: ", ")))
        .accessibilityHint("Shows the player's history")
    }

    private func history(_ record: PlayerRecord) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("History")
            VStack(spacing: 0) {
                ForEach(Array(record.tournaments.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider().overlay(Theme.Colors.separator).padding(.leading, 72)
                    }
                    Button {
                        path.append(.tournament(entry.tournamentID))
                    } label: {
                        PlayerHistoryRow(entry: entry)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .surfaceCard(padding: 0, cornerRadius: 22)
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
    @ScaledMetric(relativeTo: .title) private var valueSize: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(highlighted ? Theme.Colors.onAccent : Theme.Colors.accentText)
                .frame(width: 30, height: 30)
                .background(highlighted ? Theme.Colors.ink.opacity(0.12) : Theme.Colors.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            Text(verbatim: value)
                .font(.padelScoreboard(size: valueSize))
                .foregroundStyle(highlighted ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(verbatim: title)
                .font(.padelEyebrow)
                .textCase(.uppercase)
                .foregroundStyle(highlighted ? Theme.Colors.onAccent.opacity(0.75) : Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .surfaceCard(
            padding: Theme.Spacing.m,
            cornerRadius: 20,
            fill: highlighted ? Theme.Colors.accent : Theme.Colors.surface
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: spokenValue ?? value))
    }
}

/// W / D / L chip in a player's form line.
struct FormChip: View {
    let outcome: MatchOutcome
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 40

    var body: some View {
        Text(verbatim: outcome.letter)
            .font(.padelScoreboard(size: size * 0.45))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(outcome == .loss ? Theme.Colors.danger.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: outcome == .win ? Theme.Colors.accent.opacity(0.35) : .clear, radius: 6)
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(entry.isWin
                          ? AnyShapeStyle(LinearGradient(colors: [Theme.Colors.limeBright, Theme.Colors.limeDeep], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Theme.Colors.surfaceRaised))
                if entry.isWin {
                    Image(systemName: "trophy.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.Colors.onAccent)
                } else {
                    Text(verbatim: rankText)
                        .font(.padelScoreboard(size: 17))
                        .foregroundStyle(entry.isPodium ? Theme.Colors.accentText : Theme.Colors.textSecondary)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.tournamentName)
                    .font(.padelName.weight(.bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(verbatim: "\(entry.date.formatted(date: .abbreviated, time: .omitted)) · \(entry.format.localizedName)")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                Text(verbatim: resultLine)
                    .font(.padelMeta.monospacedDigit().weight(.semibold))
                    .foregroundStyle(entry.isCompleted ? Theme.Colors.textSecondary : Theme.Colors.accentText)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.s)
            if !entry.isCompleted {
                LiveDot(size: 7)
            }
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityHint("Opens the tournament")
        .accessibilityAddTraits(.isButton)
    }

    private var rankText: String {
        guard let rank = entry.rank else { return "–" }
        return (entry.isTied ? "=" : "") + rank.formatted()
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
