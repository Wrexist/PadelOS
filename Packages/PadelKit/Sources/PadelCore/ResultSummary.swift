import Foundation

/// Plain-text summaries for the share sheet. No network, no fake URLs.
public enum ResultSummary {
    public static func text(for tournament: Tournament, standings: Standings? = nil) -> String {
        let table = standings ?? StandingsCalculator.compute(tournament)
        var lines: [String] = []
        let state = tournament.status == .completed ? L10n.string("Final standings") : L10n.format("Standings after %lld of %lld rounds", tournament.completedRoundCount, tournament.configuration.roundCount)
        lines.append("🎾 \(tournament.name)")
        lines.append("\(tournament.configuration.format.displayName) · \(tournament.configuration.scoring.displayName) · \(state)")
        lines.append("")
        for entry in table.entries {
            let medal: String
            switch entry.rank {
            case 1: medal = "🥇"
            case 2: medal = "🥈"
            case 3: medal = "🥉"
            default: medal = "\(entry.rank)."
            }
            let tie = entry.isTied ? " " + L10n.string("(tied)") : ""
            let diff = entry.pointDifference >= 0 ? "+\(entry.pointDifference)" : "\(entry.pointDifference)"
            let withdrawn = entry.isWithdrawn ? " · " + L10n.string("withdrawn") : ""
            let unit = tournament.configuration.scoring.isSets ? L10n.string("games") : L10n.string("pts")
            lines.append("\(medal) \(entry.name) — \(entry.points) \(unit) · " + L10n.format("%lldW %lldD %lldL", entry.wins, entry.draws, entry.losses) + " · \(diff)\(tie)\(withdrawn)")
        }
        if let champion = tournament.playoffChampion {
            lines.append("")
            lines.append("🏆 " + L10n.format("Playoff winners: %@", tournament.sideName(champion)))
            if let runnerUp = tournament.playoffRunnerUp {
                lines.append(L10n.format("Runners-up: %@", tournament.sideName(runnerUp)))
            }
        }
        lines.append("")
        lines.append(L10n.string("Ranking:") + " " + table.tieBreakers.map(\.displayName).joined(separator: " → "))
        return lines.joined(separator: "\n")
    }

    /// Round-by-round results, for organisers who want the full record.
    public static func resultsText(for tournament: Tournament) -> String {
        var lines: [String] = ["🎾 " + L10n.format("%@ — results", tournament.name), ""]
        for round in tournament.rounds {
            if let stage = tournament.knockoutStage(of: round) {
                lines.append(stage.displayName)
            } else {
                lines.append(round.kind == .final ? L10n.string("Final round") : L10n.format("Round %lld", round.number))
            }
            for match in round.matches {
                let score: String
                if !match.isCompleted {
                    score = L10n.string("not played")
                } else if let sets = match.sets, tournament.configuration.scoring.isSets {
                    score = sets.summary()
                } else {
                    score = "\(match.score.a)–\(match.score.b)"
                }
                lines.append("  " + L10n.format("Court %lld", match.court) + ": \(tournament.sideName(match.sideA)) \(score) \(tournament.sideName(match.sideB))")
            }
            if !round.restingPlayerIDs.isEmpty && tournament.configuration.format.isIndividual {
                lines.append("  " + L10n.string("Resting:") + " " + round.restingPlayerIDs.map { tournament.playerName($0) }.joined(separator: ", "))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
