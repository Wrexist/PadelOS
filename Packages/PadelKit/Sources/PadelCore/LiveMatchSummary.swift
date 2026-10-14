import Foundation

/// Everything a Live Activity (Lock Screen / Dynamic Island) shows for one match,
/// computed from the tournament so the presentation layer stays trivial.
public struct LiveMatchSummary: Equatable, Sendable {
    public var tournamentName: String
    public var courtLabel: String
    public var roundLabel: String
    public var teamA: String
    public var teamB: String
    /// Big figures: points (rally scoring) or the current game points (15, 30, 40, Ad).
    public var scoreA: String
    public var scoreB: String
    /// Secondary line, e.g. "12 of 24 points", "Games 3–2 · 6-4", "Tie-break".
    public var detail: String
    /// 0...1 for fixed-total matches; nil otherwise.
    public var progress: Double?
    /// The match is decided (total reached or sets won) but not yet confirmed.
    public var isDecided: Bool
    public var isFinished: Bool

    /// Whether +1 buttons should be offered.
    public var canScore: Bool { !isDecided && !isFinished }

    public init?(tournament: Tournament, matchID: MatchID) {
        guard let match = tournament.match(matchID) else { return nil }
        let rule = tournament.scoringRule(for: match)
        let round = tournament.rounds.first { $0.number == match.roundNumber }
        tournamentName = tournament.name
        courtLabel = "Court \(match.court)"
        if let round, let stage = tournament.knockoutStage(of: round) {
            roundLabel = stage.displayName
        } else {
            roundLabel = round?.kind == .final ? "Final round" : "Round \(match.roundNumber) of \(tournament.configuration.roundCount)"
        }
        teamA = tournament.sideName(match.sideA)
        teamB = tournament.sideName(match.sideB)
        isFinished = match.isCompleted
        isDecided = ScoringEngine.isDecided(match, rule: rule)

        switch rule {
        case .sets(let rules):
            let state = match.sets ?? SetsState()
            if state.isDecided {
                scoreA = "\(state.setsWon.a)"
                scoreB = "\(state.setsWon.b)"
                detail = (isFinished ? "Final · " : "Match won · ") + state.summary()
            } else {
                scoreA = state.pointLabel(.a, rules: rules)
                scoreB = state.pointLabel(.b, rules: rules)
                var parts = ["Games \(state.games.a)–\(state.games.b)"]
                if !state.completedSets.isEmpty { parts.append(state.summary(includeCurrent: false)) }
                if let situation = state.situation(rules: rules) { parts.insert(situation, at: 0) }
                detail = parts.joined(separator: " · ")
            }
            progress = nil
        case .totalPoints(let total):
            scoreA = "\(match.score.a)"
            scoreB = "\(match.score.b)"
            detail = isFinished ? "Final" : (isDecided ? "\(total) points reached" : "\(match.score.total) of \(total) points")
            progress = total > 0 ? min(1, Double(match.score.total) / Double(total)) : nil
        case .timed(let minutes):
            scoreA = "\(match.score.a)"
            scoreB = "\(match.score.b)"
            detail = isFinished ? "Final" : "Timed match · \(minutes) min"
            progress = nil
        }
    }
}
