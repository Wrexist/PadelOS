import Foundation
import PadelCore

/// Display helpers shared by the iPhone and watch apps.
extension Tournament {
    /// "Round 2 of 6", or a completion message.
    var progressLabel: String {
        if status == .completed { return "Finished" }
        if let current = currentRoundNumber {
            return "Round \(current) of \(configuration.roundCount)"
        }
        if allRoundsCompleted { return "All rounds played" }
        return "Round \(rounds.count) of \(configuration.roundCount)"
    }

    /// Short form for tight spaces: "R2/6".
    var shortProgressLabel: String {
        guard let current = currentRoundNumber else { return "\(completedRoundCount)/\(configuration.roundCount)" }
        return "R\(current)/\(configuration.roundCount)"
    }

    /// Fraction of planned matches completed, for progress bars.
    var progressFraction: Double {
        let perRound = max(1, rounds.first?.matches.count ?? 1)
        let planned = Double(perRound * configuration.roundCount)
        let done = Double(allMatches.filter(\.isCompleted).count)
        return planned > 0 ? min(1, done / planned) : 0
    }

    /// "Americano · 8 players · 2 courts"
    var summaryLine: String {
        let participants = configuration.format == .teamAmericano
            ? "\(activeTeams.count) teams"
            : "\(activePlayers.count) players"
        let courts = "\(configuration.courtCount) court\(configuration.courtCount == 1 ? "" : "s")"
        return "\(configuration.format.displayName) · \(participants) · \(courts)"
    }

    /// Short names for one side, one per line ("Alex", "Johan").
    func sideNames(of match: Match, _ side: TeamSide) -> [String] {
        let matchSide = match.side(side)
        if let teamID = matchSide.teamID, let team = team(teamID), configuration.format == .teamAmericano {
            return [team.name]
        }
        return matchSide.playerIDs.map { playerName($0) }
    }

    /// Accessible description of a match, e.g. "Court 1. Alex and Johan 12, Lisa and Maja 8."
    func accessibilityDescription(of match: Match) -> String {
        let a = sideNames(of: match, .a).joined(separator: " and ")
        let b = sideNames(of: match, .b).joined(separator: " and ")
        let state: String
        switch match.status {
        case .scheduled: state = "Not started"
        case .inProgress: state = "In progress"
        case .completed: state = "Finished"
        }
        return "Court \(match.court). \(a) \(match.score.a), \(b) \(match.score.b). \(state)."
    }
}

extension Match {
    /// Progress through a fixed-total match (0...1); nil for timed matches.
    func progress(rule: ScoringRule) -> Double? {
        guard let total = rule.totalPoints, total > 0 else { return nil }
        return min(1, Double(score.total) / Double(total))
    }
}

extension ScoringRule {
    /// "First to 24 points" style caption used under scores.
    var scoreCaption: String {
        switch self {
        case .totalPoints(let total): "\(total) points in total"
        case .timed(let minutes): "Timed match · \(minutes) min"
        }
    }
}
