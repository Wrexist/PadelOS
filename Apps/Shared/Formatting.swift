import Foundation
import PadelCore

/// Display helpers shared by the iPhone and watch apps. All user-facing text goes through
/// `String(localized:)` so it is translated with the app's string catalog.
extension Tournament {
    /// "Round 2 of 6", "Semifinals", or a completion message.
    var progressLabel: String {
        if status == .completed { return String(localized: "Finished") }
        if let round = currentRound {
            return roundTitle(round, includeTotal: true)
        }
        if allRoundsCompleted { return String(localized: "All rounds played") }
        return String(localized: "Round \(rounds.count) of \(configuration.roundCount)")
    }

    /// "Round 3", "Round 3 of 7", "Final round", "Semifinals".
    func roundTitle(_ round: Round, includeTotal: Bool = false) -> String {
        if let stage = knockoutStage(of: round) { return stage.localizedName }
        if round.kind == .final { return String(localized: "Final round") }
        return includeTotal
            ? String(localized: "Round \(round.number) of \(configuration.roundCount)")
            : String(localized: "Round \(round.number)")
    }

    /// Short form for tight spaces: "R2/6", "SF", "F".
    var shortProgressLabel: String {
        guard let round = currentRound else { return "\(completedRoundCount)/\(configuration.totalRoundCount)" }
        if let stage = knockoutStage(of: round) { return stage.shortName }
        return String(localized: "R\(round.number)/\(configuration.roundCount)")
    }

    /// Fraction of planned matches completed, for progress bars.
    var progressFraction: Double {
        let regularMatches = rounds.filter { $0.kind != .knockout }.first?.matches.count ?? 1
        let knockoutMatches = max(0, configuration.playoff.teamCount - 1)
        let planned = Double(max(1, regularMatches) * configuration.roundCount + knockoutMatches)
        let done = Double(allMatches.filter(\.isCompleted).count)
        return planned > 0 ? min(1, done / planned) : 0
    }

    /// "Americano · 8 players · 2 courts"
    var summaryLine: String {
        let participants = configuration.format.usesTeams
            ? String(localized: "\(activeTeams.count) teams")
            : String(localized: "\(activePlayers.count) players")
        let courts = String(localized: "\(configuration.courtCount) courts")
        return "\(configuration.format.localizedName) · \(participants) · \(courts)"
    }

    /// Short names for one side, one per line ("Alex", "Johan").
    func sideNames(of match: Match, _ side: TeamSide) -> [String] {
        let matchSide = match.side(side)
        if let teamID = matchSide.teamID, let team = team(teamID), configuration.format.usesTeams {
            return [team.name]
        }
        return matchSide.playerIDs.map { playerName($0) }
    }

    /// Accessible description of a match, e.g. "Court 1. Alex and Johan 12, Lisa and Maja 8."
    func accessibilityDescription(of match: Match) -> String {
        let separator = String(localized: " and ")
        let a = sideNames(of: match, .a).joined(separator: separator)
        let b = sideNames(of: match, .b).joined(separator: separator)
        let state: String
        switch match.status {
        case .scheduled: state = String(localized: "Not started")
        case .inProgress: state = String(localized: "In progress")
        case .completed: state = String(localized: "Finished")
        }
        if let sets = match.sets, scoringRule(for: match).isSets {
            let summary = sets.summary()
            let detail = summary.isEmpty ? String(localized: "no games yet") : String(localized: "sets \(summary)")
            return String(localized: "Court \(match.court). \(a) versus \(b), \(detail). \(state).")
        }
        return String(localized: "Court \(match.court). \(a) \(match.score.a), \(b) \(match.score.b). \(state).")
    }
}

extension KnockoutStage {
    var localizedName: String {
        switch self {
        case .final: String(localized: "Final")
        case .semifinal: String(localized: "Semifinals")
        case .quarterfinal: String(localized: "Quarterfinals")
        }
    }

    /// Two-letter abbreviation for the watch.
    var shortName: String {
        switch self {
        case .final: String(localized: "Final", comment: "Short label for the final on the watch")
        case .semifinal: String(localized: "SF", comment: "Abbreviation for semifinal")
        case .quarterfinal: String(localized: "QF", comment: "Abbreviation for quarterfinal")
        }
    }
}

extension TournamentFormat {
    var localizedName: String {
        switch self {
        case .americano: String(localized: "Americano")
        case .mexicano: String(localized: "Mexicano")
        case .mixedAmericano: String(localized: "Mixed Americano")
        case .mixicano: String(localized: "Mixicano")
        case .teamAmericano: String(localized: "Team Americano")
        case .teamMexicano: String(localized: "Team Mexicano")
        case .swiss: String(localized: "Swiss")
        case .kingOfTheCourt: String(localized: "King of the Court")
        }
    }

    var localizedSummary: String {
        switch self {
        case .americano: String(localized: "Individual ranking, rotating partners")
        case .mexicano: String(localized: "Pairings based on the latest standings")
        case .mixedAmericano: String(localized: "Every team has one player from each group")
        case .mixicano: String(localized: "Mexicano with one player from each group per team")
        case .teamAmericano: String(localized: "Fixed doubles teams, team ranking")
        case .teamMexicano: String(localized: "Fixed teams paired by the latest standings")
        case .swiss: String(localized: "Fixed teams meet teams with the same record, no rematches")
        case .kingOfTheCourt: String(localized: "Winners move up a court, losers move down")
        }
    }
}

extension Match {
    /// Progress through a fixed-total match (0...1); nil for timed matches.
    func progress(rule: ScoringRule) -> Double? {
        guard let total = rule.totalPoints, total > 0 else { return nil }
        return min(1, Double(score.total) / Double(total))
    }

    /// Compact result: "15–9" for points, "6-4 3-6 [10-8]" for games and sets.
    func resultText(rule: ScoringRule) -> String {
        if rule.isSets, let sets {
            let summary = sets.summary()
            return summary.isEmpty ? "0-0" : summary
        }
        return "\(score.a)–\(score.b)"
    }
}

extension ScoringRule {
    /// "24 points in total" style caption used under scores.
    var scoreCaption: String {
        switch self {
        case .totalPoints(let total): String(localized: "\(total) points in total")
        case .timed(let minutes): String(localized: "Timed match · \(minutes) min")
        case .sets(let rules): rules.localizedName
        }
    }

    /// "24 points", "12 min", "1 set · golden point".
    var localizedName: String {
        switch self {
        case .totalPoints(let total): String(localized: "\(total) points")
        case .timed(let minutes): String(localized: "\(minutes) min")
        case .sets(let rules): rules.localizedName
        }
    }

    /// Unit shown in standings.
    var localizedUnit: String {
        isSets ? String(localized: "games") : String(localized: "points")
    }
}

extension SetsRules {
    var localizedName: String {
        var parts: [String] = []
        if setsToWin == 1 {
            parts.append(gamesPerSet == 6 ? String(localized: "1 set") : String(localized: "1 set to \(gamesPerSet)"))
        } else {
            parts.append(String(localized: "Best of \(setsToWin * 2 - 1) sets"))
        }
        if superTieBreakDecider && setsToWin > 1 { parts.append(String(localized: "super tie-break")) }
        parts.append(goldenPoint ? String(localized: "golden point") : String(localized: "advantage"))
        return parts.joined(separator: " · ")
    }
}

extension PlayoffSize {
    var localizedName: String {
        switch self {
        case .none: String(localized: "No playoffs")
        case .final: String(localized: "Final (top 2)")
        case .semifinals: String(localized: "Semifinals (top 4)")
        case .quarterfinals: String(localized: "Quarterfinals (top 8)")
        }
    }
}

extension RestCompensation {
    var localizedName: String {
        switch self {
        case .none: String(localized: "No points")
        case .halfMatchTotal: String(localized: "Half the match total")
        }
    }
}

extension MexicanoPairingPattern {
    var localizedName: String {
        switch self {
        case .oneFourVsTwoThree: String(localized: "1 & 4 vs 2 & 3")
        case .oneThreeVsTwoFour: String(localized: "1 & 3 vs 2 & 4")
        }
    }
}

extension MexicanoFirstRound {
    var localizedName: String {
        switch self {
        case .random: String(localized: "Random draw")
        case .listOrder: String(localized: "Player list order")
        }
    }
}
