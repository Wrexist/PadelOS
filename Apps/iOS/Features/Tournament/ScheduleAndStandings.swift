import SwiftUI
import PadelCore
import PadelStore

// MARK: - Schedule

/// Every round on a vertical timeline: played rounds checked off, the current one lit.
struct ScheduleTab: View {
    let tournament: Tournament
    @Binding var path: [Route]
    @Binding var resultEntry: MatchID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tournament.rounds.enumerated()), id: \.element.id) { index, round in
                timelineRow(phase: phase(round), isLast: index == tournament.rounds.count - 1 && remaining == 0) {
                    roundCard(round)
                }
                .staggeredAppear(index)
            }
            if remaining > 0 {
                timelineRow(phase: .upcoming, isLast: true) {
                    EmptyStateView(
                        symbol: "wand.and.stars",
                        title: "\(remaining) more rounds to come",
                        message: tournament.rounds.count >= tournament.configuration.roundCount
                            ? "Playoff matches are drawn from the standings after the last regular round."
                            : !tournament.configuration.format.hasPrecomputedSchedule
                                ? "Each round is drawn from the latest standings when the previous one ends."
                                : "The final round is drawn from the standings after the last regular round."
                    )
                    .surfaceCard(padding: 0)
                }
                .staggeredAppear(tournament.rounds.count)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    private var remaining: Int {
        tournament.configuration.totalRoundCount - tournament.rounds.count
    }

    /// A rail on the leading side (dot plus a line down to the next round) beside the card.
    private func timelineRow<Content: View>(phase: TimelineNode.Phase, isLast: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            TimelineNode(phase: phase)
            content()
                .padding(.bottom, Theme.Spacing.l)
        }
        .background(alignment: .topLeading) {
            if !isLast {
                Rectangle()
                    .fill(phase == .done ? Theme.Colors.accent.opacity(0.6) : Theme.Colors.separator)
                    .frame(width: 2)
                    .padding(.top, 26)
                    .padding(.leading, 10)
                    .accessibilityHidden(true)
            }
        }
    }

    private func phase(_ round: Round) -> TimelineNode.Phase {
        if round.isCompleted { return .done }
        if round.number == tournament.currentRoundNumber { return .current }
        return .upcoming
    }

    private func roundCard(_ round: Round) -> some View {
        let isCurrent = round.number == tournament.currentRoundNumber
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(verbatim: tournament.roundTitle(round), trailing: roundState(round))
            VStack(spacing: 0) {
                ForEach(round.matches) { match in
                    Button {
                        path.append(.match(tournament.id, match.id))
                    } label: {
                        ScheduleRow(tournament: tournament, match: match)
                    }
                    .buttonStyle(.pressable)
                    .contextMenu {
                        if tournament.status == .active {
                            Button {
                                resultEntry = match.id
                            } label: {
                                Label(match.isCompleted ? "Correct Result" : "Enter Result", systemImage: "pencil")
                            }
                        }
                    }
                    if match.id != round.matches.last?.id {
                        Divider().overlay(Theme.Colors.separator)
                    }
                }
                if !restingNames(round).isEmpty {
                    Divider().overlay(Theme.Colors.separator)
                    HStack {
                        Image(systemName: "cup.and.saucer")
                            .accessibilityHidden(true)
                        Text("Resting: \(restingNames(round).joined(separator: ", "))")
                            .lineLimit(2)
                        Spacer()
                    }
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.m)
                }
            }
            .surfaceCard(padding: 0, cornerRadius: 20, highlight: isCurrent ? Theme.Colors.accent.opacity(0.6) : nil)
        }
    }

    private func roundState(_ round: Round) -> String {
        switch round.status {
        case .completed: String(localized: "Completed")
        case .inProgress: String(localized: "In progress")
        case .upcoming: round.number == tournament.currentRoundNumber ? String(localized: "Next") : String(localized: "Upcoming")
        }
    }

    private func restingNames(_ round: Round) -> [String] {
        tournament.configuration.format.usesTeams
            ? round.restingTeamIDs.compactMap { tournament.team($0)?.name }
            : round.restingPlayerIDs.map { tournament.playerName($0) }
    }
}

/// Dot of the schedule timeline.
struct TimelineNode: View {
    enum Phase { case done, current, upcoming }
    let phase: Phase

    var body: some View {
        ZStack {
            switch phase {
            case .done:
                Circle().fill(Theme.Colors.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Theme.Colors.onAccent)
            case .current:
                Circle().strokeBorder(Theme.Colors.accentText, lineWidth: 2)
                LiveDot(size: 8)
            case .upcoming:
                Circle().strokeBorder(Theme.Colors.separator, lineWidth: 2)
            }
        }
        .frame(width: 22, height: 22)
        .padding(.top, 2)
        .accessibilityHidden(true)
    }
}

struct ScheduleRow: View {
    let tournament: Tournament
    let match: Match

    var body: some View {
        let winner = match.isCompleted ? ScoringEngine.winner(of: match) : nil
        HStack(spacing: Theme.Spacing.m) {
            Text("C\(match.court)")
                .font(.padelEyebrow)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: tournament.sideName(match.sideA))
                    .fontWeight(winner == .a ? .bold : .regular)
                Text(verbatim: tournament.sideName(match.sideB))
                    .fontWeight(winner == .b ? .bold : .regular)
            }
            .font(.padelMeta)
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(1)
            Spacer()
            if match.hasStarted && tournament.configuration.scoring.isSets {
                Text(verbatim: match.resultText(rule: tournament.scoringRule(for: match)))
                    .font(.padelMeta.monospacedDigit().weight(.semibold))
                    .foregroundStyle(match.isCompleted ? Theme.Colors.textPrimary : Theme.Colors.accentText)
            } else if match.hasStarted {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(match.score.a)")
                        .foregroundStyle(winner == .a ? Theme.Colors.accentText : Theme.Colors.textPrimary)
                    Text("\(match.score.b)")
                        .foregroundStyle(winner == .b ? Theme.Colors.accentText : Theme.Colors.textPrimary)
                }
                .font(.padelScoreboard(size: 17))
                .foregroundStyle(match.isCompleted ? Theme.Colors.textPrimary : Theme.Colors.accentText)
            }
            if match.status == .inProgress {
                LiveDot(size: 7)
            } else {
                Image(systemName: match.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(match.isCompleted ? Theme.Colors.textSecondary : Theme.Colors.separator)
                    .accessibilityHidden(true)
            }
        }
        .padding(Theme.Spacing.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tournament.accessibilityDescription(of: match))
        .accessibilityHint("Opens the match")
    }
}

// MARK: - Standings

struct StandingsTab: View {
    let tournament: Tournament
    @State private var selected: StandingEntry?

    var body: some View {
        let standings = StandingsCalculator.compute(tournament)
        let movement = rankMovement(standings)
        let unit = tournament.configuration.scoring.unitName
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if tournament.configuration.playoff != .none {
                BracketView(tournament: tournament)
            }
            if standings.completedMatches == 0 {
                EmptyStateView(symbol: "list.number", title: "No results yet", message: "Standings appear as soon as the first match is finished.")
                    .surfaceCard(padding: 0)
            } else if standings.entries.count >= 3 {
                Podium(entries: Array(standings.entries.prefix(3)), unit: unit)
                    .padding(.top, Theme.Spacing.s)
            }
            VStack(spacing: 0) {
                header
                ForEach(standings.entries) { entry in
                    Divider().overlay(Theme.Colors.separator)
                    Button {
                        selected = entry
                    } label: {
                        StandingRow(entry: entry, unit: unit, movement: movement[entry.id])
                    }
                    .buttonStyle(.pressable)
                }
            }
            .surfaceCard(padding: 0, cornerRadius: 22)
            .animation(Motion.smooth, value: standings.entries.map(\.id))
            .accessibilityIdentifier("standingsTable")

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Ranking order")
                    .font(.padelMeta.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(standings.tieBreakers.map(\.displayName).joined(separator: " → ")). Equal on all of these means a shared position (=).")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if tournament.configuration.restPoints > 0 {
                    Text("Resting earns \(tournament.configuration.restPoints) points per round.")
                        .font(.padelMeta)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)

            ShareResultsButton(tournament: tournament, standings: standings)
        }
        .padding(.top, Theme.Spacing.s)
        .sheet(item: $selected) { entry in
            PlayerResultsSheet(tournament: tournament, entry: entry)
        }
    }

    /// Places gained (positive) or lost since the standings before the latest results.
    private func rankMovement(_ standings: Standings) -> [StandingSubject: Int] {
        let regular = tournament.rounds.filter { $0.kind != .knockout }
        let lastCompleted = regular.filter(\.isCompleted).map(\.number).max() ?? 0
        let currentHasResults = regular.contains { !$0.isCompleted && $0.matches.contains(where: \.isCompleted) }
        let baseline = currentHasResults ? lastCompleted : lastCompleted - 1
        guard baseline >= 1 else { return [:] }
        let previous = StandingsCalculator.compute(tournament, throughRound: baseline)
        guard previous.completedMatches > 0 else { return [:] }
        var result: [StandingSubject: Int] = [:]
        for entry in standings.entries {
            if let before = previous.entry(for: entry.subject) {
                result[entry.subject] = before.rank - entry.rank
            }
        }
        return result
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: 36, alignment: .leading)
            Text(tournament.configuration.format.usesTeams ? "Team" : "Player")
            Spacer()
            Group {
                Text(tournament.configuration.scoring.isSets ? "Gms" : "Pts")
                Text("W")
                Text("L")
                Text("Diff")
            }
            .frame(width: 42, alignment: .trailing)
        }
        .font(.padelEyebrow)
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.m)
        .accessibilityHidden(true)
    }
}

struct StandingRow: View {
    let entry: StandingEntry
    var unit = "points"
    /// Places gained since the previous results (negative: lost).
    var movement: Int?

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                Text(entry.isTied ? "=\(entry.rank)" : "\(entry.rank)")
                    .font(.padelScoreboard(size: 17))
                    .foregroundStyle(entry.rank == 1 ? Theme.Colors.accentText : Theme.Colors.textSecondary)
                    .contentTransition(.numericText(value: Double(entry.rank)))
                if let movement, movement != 0 {
                    Image(systemName: movement > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(movement > 0 ? Theme.Colors.accentText : Theme.Colors.danger)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 36, alignment: .leading)
            PlayerAvatar(name: entry.name, size: 28, ring: entry.rank == 1 ? Theme.Colors.accent : nil)
                .padding(.trailing, Theme.Spacing.s)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: entry.name)
                    .font(.padelMeta.weight(entry.rank == 1 ? .bold : .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                if entry.isWithdrawn {
                    Text("Withdrawn")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer(minLength: Theme.Spacing.xs)
            Group {
                Text("\(entry.points)")
                    .font(.padelScoreboard(size: 17))
                    .contentTransition(.numericText(value: Double(entry.points)))
                Text("\(entry.wins)")
                Text("\(entry.losses)")
                Text(entry.pointDifference > 0 ? "+\(entry.pointDifference)" : "\(entry.pointDifference)")
            }
            .font(.padelMeta.monospacedDigit())
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.m)
        .background(alignment: .leading) {
            if entry.rank == 1 {
                LinearGradient(colors: [Theme.Colors.accent.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows round-by-round results")
    }

    private var accessibilityText: String {
        let position = entry.isTied ? String(localized: "Shared position \(entry.rank)") : String(localized: "Position \(entry.rank)")
        var text = position + ", " + String(localized: "\(entry.name), \(entry.points) \(unit), \(entry.wins) wins, \(entry.draws) draws, \(entry.losses) losses, difference \(entry.pointDifference)")
        if entry.isWithdrawn { text += ", " + String(localized: "withdrawn") }
        return text
    }
}

/// One step of the podium.
struct PodiumItem: Identifiable {
    let id: String
    let name: String
    /// The big number under the name ("28", "67 %").
    let value: String
    /// For the rolling-digit transition, when the value is a number.
    var numeric: Double?
    /// "1", "=2"…
    let rankLabel: String
    let accessibilityLabel: String
}

/// Top three on a podium that rises when shown: second, first, third.
struct Podium: View {
    let items: [PodiumItem]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var raised = false

    private static let heights: [CGFloat] = [118, 86, 64]

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
            ForEach([1, 0, 2], id: \.self) { place in
                if items.indices.contains(place) {
                    column(items[place], place: place)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { raised = true }
    }

    private func column(_ item: PodiumItem, place: Int) -> some View {
        let first = place == 0
        let up = raised || reduceMotion
        return VStack(spacing: Theme.Spacing.s) {
            if first {
                Image(systemName: "crown.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.accentText)
                    .symbolEffect(.bounce, value: raised)
                    .accessibilityHidden(true)
            }
            PlayerAvatar(name: item.name, size: first ? 58 : 46, ring: first ? Theme.Colors.accent : nil)
                .shadow(color: first ? Theme.Colors.accent.opacity(0.45) : .clear, radius: 12)
            Text(verbatim: item.name)
                .font(.padelMeta.weight(.bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: item.value)
                .font(.padelScoreboard(size: first ? 26 : 20))
                .foregroundStyle(first ? Theme.Colors.accentText : Theme.Colors.textPrimary)
                .contentTransition(item.numeric.map { ContentTransition.numericText(value: $0) } ?? ContentTransition.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 14, style: .continuous)
                    .fill(first
                          ? AnyShapeStyle(LinearGradient(colors: [Theme.Colors.limeBright, Theme.Colors.limeDeep], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Theme.Colors.surfaceRaised))
                Text(verbatim: item.rankLabel)
                    .font(.padelScoreboard(size: first ? 34 : 26))
                    .foregroundStyle(first ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                    .padding(.top, Theme.Spacing.s)
                    .opacity(up ? 1 : 0)
            }
            .frame(height: up ? Self.heights[place] : 10)
            .animation(reduceMotion ? Motion.fade : Motion.hero.delay(Double(2 - place) * 0.12 + 0.1), value: raised)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.accessibilityLabel))
    }
}

extension Podium {
    /// The top of the tournament standings.
    init(entries: [StandingEntry], unit: String) {
        self.init(items: entries.map { entry in
            let position = entry.isTied ? String(localized: "Shared position \(entry.rank)") : String(localized: "Position \(entry.rank)")
            return PodiumItem(
                id: "\(entry.id)",
                name: entry.name,
                value: entry.points.formatted(),
                numeric: Double(entry.points),
                rankLabel: (entry.isTied ? "=" : "") + entry.rank.formatted(),
                accessibilityLabel: [position, entry.name, String(localized: "\(entry.points) \(unit)")].joined(separator: ", ")
            )
        })
    }
}

struct PlayerResultsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tournament: Tournament
    let entry: StandingEntry

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Theme.Spacing.s) {
                        stat(tournament.configuration.scoring.isSets ? String(localized: "Games") : String(localized: "Points"), "\(entry.points)", highlighted: true)
                        stat(String(localized: "Played"), "\(entry.played)")
                        stat(String(localized: "W-D-L"), "\(entry.wins)-\(entry.draws)-\(entry.losses)")
                        stat(String(localized: "Diff"), entry.pointDifference > 0 ? "+\(entry.pointDifference)" : "\(entry.pointDifference)")
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                } header: {
                    HStack(spacing: Theme.Spacing.m) {
                        PlayerAvatar(name: entry.name, size: 44, ring: entry.rank == 1 ? Theme.Colors.accent : nil)
                        Text(entry.isTied ? "=\(entry.rank)" : "\(entry.rank)")
                            .font(.padelScoreboard(size: 28))
                            .foregroundStyle(Theme.Colors.accentText)
                    }
                    .textCase(nil)
                    .padding(.bottom, Theme.Spacing.s)
                }
                Section("Round by round") {
                    ForEach(entry.roundResults) { result in
                        HStack {
                            Text("Round \(result.roundNumber)")
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            Text(verbatim: describe(result))
                                .foregroundStyle(color(result))
                                .monospacedDigit()
                        }
                        .font(.padelMeta)
                        .accessibilityElement(children: .combine)
                    }
                }
                .listRowBackground(Theme.Colors.surface)
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(Text(verbatim: entry.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func stat(_ title: String, _ value: String, highlighted: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value)
                .font(.padelScoreboard(size: 24))
                .foregroundStyle(highlighted ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(highlighted ? Theme.Colors.onAccent.opacity(0.75) : Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(highlighted ? Theme.Colors.accent : Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func color(_ result: RoundResult) -> Color {
        switch result.outcome {
        case .won: Theme.Colors.accentText
        case .lost: Theme.Colors.textSecondary
        default: Theme.Colors.textPrimary
        }
    }

    private func describe(_ result: RoundResult) -> String {
        switch result.outcome {
        case .won: String(localized: "Won \(result.pointsFor)–\(result.pointsAgainst)")
        case .lost: String(localized: "Lost \(result.pointsFor)–\(result.pointsAgainst)")
        case .drew: String(localized: "Draw \(result.pointsFor)–\(result.pointsAgainst)")
        case .rested: result.creditedPoints > 0 ? String(localized: "Rested (+\(result.creditedPoints))") : String(localized: "Rested")
        case .notPlayed: String(localized: "Not played yet")
        }
    }
}
