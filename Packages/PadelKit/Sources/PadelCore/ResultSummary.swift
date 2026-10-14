import Foundation

/// Plain-text summaries for the share sheet. No network, no fake URLs.
public enum ResultSummary {
    public static func text(for tournament: Tournament, standings: Standings? = nil) -> String {
        let table = standings ?? StandingsCalculator.compute(tournament)
        var lines: [String] = []
        let state = tournament.status == .completed ? "Final standings" : "Standings after \(tournament.completedRoundCount) of \(tournament.configuration.roundCount) rounds"
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
            let tie = entry.isTied ? " (tied)" : ""
            let diff = entry.pointDifference >= 0 ? "+\(entry.pointDifference)" : "\(entry.pointDifference)"
            let withdrawn = entry.isWithdrawn ? " · withdrawn" : ""
            lines.append("\(medal) \(entry.name) — \(entry.points) pts · \(entry.wins)W \(entry.draws)D \(entry.losses)L · \(diff)\(tie)\(withdrawn)")
        }
        lines.append("")
        lines.append("Ranking: " + table.tieBreakers.map(\.displayName).joined(separator: " → "))
        return lines.joined(separator: "\n")
    }

    /// Round-by-round results, for organisers who want the full record.
    public static func resultsText(for tournament: Tournament) -> String {
        var lines: [String] = ["🎾 \(tournament.name) — results", ""]
        for round in tournament.rounds {
            lines.append(round.kind == .final ? "Final round" : "Round \(round.number)")
            for match in round.matches {
                let score = match.isCompleted ? "\(match.score.a)–\(match.score.b)" : "not played"
                lines.append("  Court \(match.court): \(tournament.sideName(match.sideA)) \(score) \(tournament.sideName(match.sideB))")
            }
            if !round.restingPlayerIDs.isEmpty && tournament.configuration.format.isIndividual {
                lines.append("  Resting: " + round.restingPlayerIDs.map { tournament.playerName($0) }.joined(separator: ", "))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
