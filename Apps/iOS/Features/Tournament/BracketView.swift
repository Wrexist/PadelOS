import SwiftUI
import PadelCore

/// Knockout bracket: one column per stage, played stages show results, future stages
/// show placeholders. The playoff winners get a banner once the final is decided.
struct BracketView: View {
    let tournament: Tournament
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var stages: [(stage: KnockoutStage, round: Round?)] {
        let playoff = tournament.configuration.playoff
        return (0..<playoff.stageCount).compactMap { index in
            guard let stage = KnockoutStage(rawValue: playoff.teamCount >> index) else { return nil }
            let round = tournament.rounds.first { $0.number == tournament.configuration.roundCount + 1 + index }
            return (stage, round)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: String(localized: "Playoffs"), trailing: tournament.configuration.playoff.localizedName)
            if let champion = tournament.playoffChampion {
                championBanner(champion)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: Theme.Spacing.m) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { index, entry in
                        column(entry.stage, round: entry.round)
                            .opacity(appeared || reduceMotion ? 1 : 0)
                            .offset(x: appeared || reduceMotion ? 0 : 24)
                            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(Double(index) * 0.08), value: appeared)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            if stages.first?.round == nil {
                Text("The bracket is drawn from the standings after round \(tournament.configuration.roundCount).")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bracket")
    }

    private func championBanner(_ champion: MatchSide) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(width: 48, height: 48)
                .background(Theme.Colors.accent, in: Circle())
                .symbolEffect(.bounce, value: appeared)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Playoff winners")
                    .font(.padelOverline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                Text(tournament.sideName(champion))
                    .font(.padelSection)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            Spacer()
        }
        .cardStyle(padding: Theme.Spacing.m)
        .accessibilityElement(children: .combine)
    }

    private func column(_ stage: KnockoutStage, round: Round?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(stage.localizedName)
                .font(.padelMeta.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            if let round {
                ForEach(round.matches) { match in
                    BracketMatchCell(tournament: tournament, match: match)
                }
            } else {
                ForEach(0..<max(1, stage.rawValue / 2), id: \.self) { _ in
                    BracketPlaceholderCell()
                }
            }
        }
        .frame(width: 200, alignment: .leading)
    }
}

struct BracketMatchCell: View {
    let tournament: Tournament
    let match: Match

    var body: some View {
        let winner = match.isCompleted ? ScoringEngine.winner(of: match) : nil
        let rule = tournament.scoringRule(for: match)
        VStack(spacing: 0) {
            row(.a, winner: winner, rule: rule)
            Divider().overlay(Theme.Colors.separator)
            row(.b, winner: winner, rule: rule)
        }
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(match.status == .inProgress ? Theme.Colors.accent : .clear, lineWidth: 1.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tournament.accessibilityDescription(of: match))
    }

    private func row(_ side: TeamSide, winner: TeamSide?, rule: ScoringRule) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(tournament.sideName(match.side(side)))
                .font(.padelMeta.weight(winner == side ? .bold : .regular))
                .foregroundStyle(winner == nil || winner == side ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if match.hasStarted {
                Text(rule.isSets ? "\(match.sets?.setsWon[side] ?? 0)" : "\(match.score[side])")
                    .font(.padelMeta.monospacedDigit().weight(.semibold))
                    .foregroundStyle(winner == side ? Theme.Colors.accentText : Theme.Colors.textSecondary)
            }
            if winner == side {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accentText)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
    }
}

struct BracketPlaceholderCell: View {
    var body: some View {
        VStack(spacing: 0) {
            placeholderRow
            Divider().overlay(Theme.Colors.separator)
            placeholderRow
        }
        .background(Theme.Colors.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(Theme.Colors.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
        .accessibilityLabel(Text("To be decided"))
    }

    private var placeholderRow: some View {
        HStack {
            Text("To be decided")
                .font(.padelMeta)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
    }
}
