import SwiftUI
import PadelCore
import PadelStore

// MARK: - Schedule

struct ScheduleTab: View {
    let tournament: Tournament
    @Binding var path: [Route]
    @Binding var resultEntry: MatchID?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            ForEach(tournament.rounds) { round in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionHeader(title: roundTitle(round), trailing: roundState(round))
                    VStack(spacing: 0) {
                        ForEach(round.matches) { match in
                            Button {
                                path.append(.match(tournament.id, match.id))
                            } label: {
                                ScheduleRow(tournament: tournament, match: match)
                            }
                            .buttonStyle(.plain)
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
                                Text("Resting: " + restingNames(round).joined(separator: ", "))
                                    .lineLimit(2)
                                Spacer()
                            }
                            .font(.padelMeta)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(Theme.Spacing.m)
                        }
                    }
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                            .strokeBorder(round.number == tournament.currentRoundNumber ? Theme.Colors.accent.opacity(0.6) : .clear, lineWidth: 1.5)
                    )
                }
            }
            let remaining = tournament.configuration.roundCount - tournament.rounds.count
            if remaining > 0 {
                EmptyStateView(
                    symbol: "wand.and.stars",
                    title: "\(remaining) more round\(remaining == 1 ? "" : "s") to come",
                    message: tournament.configuration.format == .mexicano
                        ? "Mexicano pairs players by the latest standings, so each round is drawn when the previous one ends."
                        : "The final round is drawn from the standings after the last regular round."
                )
                .cardStyle()
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    private func roundTitle(_ round: Round) -> String {
        round.kind == .final ? "Final round" : "Round \(round.number)"
    }

    private func roundState(_ round: Round) -> String {
        switch round.status {
        case .completed: "Completed"
        case .inProgress: "In progress"
        case .upcoming: round.number == tournament.currentRoundNumber ? "Next" : "Upcoming"
        }
    }

    private func restingNames(_ round: Round) -> [String] {
        tournament.configuration.format == .teamAmericano
            ? round.restingTeamIDs.compactMap { tournament.team($0)?.name }
            : round.restingPlayerIDs.map { tournament.playerName($0) }
    }
}

struct ScheduleRow: View {
    let tournament: Tournament
    let match: Match

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Text("C\(match.court)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tournament.sideName(match.sideA))
                    .fontWeight(match.score.winner == .a && match.isCompleted ? .semibold : .regular)
                Text(tournament.sideName(match.sideB))
                    .fontWeight(match.score.winner == .b && match.isCompleted ? .semibold : .regular)
            }
            .font(.padelMeta)
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(1)
            Spacer()
            if match.hasStarted {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(match.score.a)")
                    Text("\(match.score.b)")
                }
                .font(.padelMeta.monospacedDigit().weight(.semibold))
                .foregroundStyle(match.isCompleted ? Theme.Colors.textPrimary : Theme.Colors.accentText)
            }
            Image(systemName: match.isCompleted ? "checkmark.circle.fill" : (match.hasStarted ? "circle.dotted" : "circle"))
                .foregroundStyle(match.isCompleted ? Theme.Colors.textSecondary : Theme.Colors.accentText)
                .accessibilityHidden(true)
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
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if standings.completedMatches == 0 {
                EmptyStateView(symbol: "list.number", title: "No results yet", message: "Standings appear as soon as the first match is finished.")
                    .cardStyle()
            }
            VStack(spacing: 0) {
                header
                ForEach(standings.entries) { entry in
                    Divider().overlay(Theme.Colors.separator)
                    Button {
                        selected = entry
                    } label: {
                        StandingRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .accessibilityIdentifier("standingsTable")

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Ranking order")
                    .font(.padelMeta.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(standings.tieBreakers.map(\.displayName).joined(separator: " → ") + ". Equal on all of these means a shared position (=).")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
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

    private var header: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: 36, alignment: .leading)
            Text(tournament.configuration.format == .teamAmericano ? "Team" : "Player")
            Spacer()
            Group {
                Text("Pts")
                Text("W")
                Text("L")
                Text("Diff")
            }
            .frame(width: 42, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityHidden(true)
    }
}

struct StandingRow: View {
    let entry: StandingEntry

    var body: some View {
        HStack(spacing: 0) {
            Text(entry.isTied ? "=\(entry.rank)" : "\(entry.rank)")
                .font(.padelMeta.monospacedDigit().weight(.semibold))
                .foregroundStyle(entry.rank == 1 ? Theme.Colors.accentText : Theme.Colors.textSecondary)
                .frame(width: 36, alignment: .leading)
            PlayerAvatar(name: entry.name, size: 26)
                .padding(.trailing, Theme.Spacing.s)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.name)
                    .font(.padelMeta.weight(.medium))
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
                Text("\(entry.points)").fontWeight(.bold)
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
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows round-by-round results")
    }

    private var accessibilityText: String {
        var text = "\(entry.isTied ? "Shared " : "")position \(entry.rank), \(entry.name), \(entry.points) points, \(entry.wins) wins, \(entry.draws) draws, \(entry.losses) losses, difference \(entry.pointDifference)"
        if entry.isWithdrawn { text += ", withdrawn" }
        return text
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
                    HStack {
                        stat("Points", "\(entry.points)")
                        stat("Played", "\(entry.played)")
                        stat("W-D-L", "\(entry.wins)-\(entry.draws)-\(entry.losses)")
                        stat("Diff", entry.pointDifference > 0 ? "+\(entry.pointDifference)" : "\(entry.pointDifference)")
                    }
                }
                .listRowBackground(Theme.Colors.surface)
                Section("Round by round") {
                    ForEach(entry.roundResults) { result in
                        HStack {
                            Text("Round \(result.roundNumber)")
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            Text(describe(result))
                                .foregroundStyle(Theme.Colors.textSecondary)
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
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.padelSection.monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
            Text(title).font(.caption2).foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func describe(_ result: RoundResult) -> String {
        switch result.outcome {
        case .won: "Won \(result.pointsFor)–\(result.pointsAgainst)"
        case .lost: "Lost \(result.pointsFor)–\(result.pointsAgainst)"
        case .drew: "Draw \(result.pointsFor)–\(result.pointsAgainst)"
        case .rested: result.creditedPoints > 0 ? "Rested (+\(result.creditedPoints))" : "Rested"
        case .notPlayed: "Not played yet"
        }
    }
}
