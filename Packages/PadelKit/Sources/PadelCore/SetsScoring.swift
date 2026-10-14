import Foundation

/// Traditional padel scoring: points (0, 15, 30, 40), games, sets, tie-breaks.
public struct SetsRules: Codable, Hashable, Sendable {
    /// 1 = a single set, 2 = best of three.
    public var setsToWin: Int
    /// Games needed to win a set (6 standard, 4 for short sets).
    public var gamesPerSet: Int
    /// "Punto de oro": at deuce the next point wins the game (no advantage).
    public var goldenPoint: Bool
    /// Play a tie-break at games-all (6–6). Without it a set needs a two-game lead.
    public var tieBreak: Bool
    public var tieBreakPoints: Int
    /// The deciding set is replaced by a match tie-break to 10 (only with best of three).
    public var superTieBreakDecider: Bool

    public init(setsToWin: Int = 1, gamesPerSet: Int = 6, goldenPoint: Bool = true, tieBreak: Bool = true, tieBreakPoints: Int = 7, superTieBreakDecider: Bool = false) {
        self.setsToWin = setsToWin
        self.gamesPerSet = gamesPerSet
        self.goldenPoint = goldenPoint
        self.tieBreak = tieBreak
        self.tieBreakPoints = tieBreakPoints
        self.superTieBreakDecider = superTieBreakDecider
    }

    public static let superTieBreakPoints = 10

    /// Common presets offered in the app.
    public static let oneSet = SetsRules(setsToWin: 1, gamesPerSet: 6, goldenPoint: true)
    public static let shortSet = SetsRules(setsToWin: 1, gamesPerSet: 4, goldenPoint: true)
    public static let bestOfThree = SetsRules(setsToWin: 2, gamesPerSet: 6, goldenPoint: false)
    public static let bestOfThreeSuperTieBreak = SetsRules(setsToWin: 2, gamesPerSet: 6, goldenPoint: true, superTieBreakDecider: true)
    public static let presets: [SetsRules] = [.oneSet, .shortSet, .bestOfThreeSuperTieBreak, .bestOfThree]

    public var displayName: String {
        var parts: [String] = []
        if setsToWin == 1 {
            parts.append(gamesPerSet == 6 ? "1 set" : "1 set to \(gamesPerSet)")
        } else {
            parts.append("Best of \(setsToWin * 2 - 1) sets")
        }
        if superTieBreakDecider && setsToWin > 1 { parts.append("super tie-break") }
        parts.append(goldenPoint ? "golden point" : "advantage")
        return parts.joined(separator: " · ")
    }

    /// Rough duration for planning rounds.
    public var estimatedMinutes: Int {
        let perSet = gamesPerSet >= 6 ? 35 : 22
        if setsToWin == 1 { return perSet }
        return perSet * 2 + (superTieBreakDecider ? 10 : perSet / 2)
    }

    var isValid: Bool {
        (1...3).contains(setsToWin) && (2...9).contains(gamesPerSet) && (5...15).contains(tieBreakPoints)
    }

    /// Whether a finished set score is possible under these rules. `isSuperTieBreak` means
    /// the "set" is a match tie-break scored in points.
    public func isLegalSetScore(_ set: Score, isSuperTieBreak: Bool) -> Bool {
        let high = max(set.a, set.b), low = min(set.a, set.b)
        if isSuperTieBreak {
            return high >= Self.superTieBreakPoints && high - low >= 2 && (high == Self.superTieBreakPoints || high - low == 2)
        }
        let n = gamesPerSet
        if high == n && low <= n - 2 { return true }
        if high == n + 1 && low == n - 1 { return true }
        if tieBreak { return high == n + 1 && low == n }
        // Advantage set: any two-game lead beyond n.
        return high > n && high - low == 2
    }
}

/// Running state of a games/sets match, rebuilt by replaying rally points.
public struct SetsState: Codable, Hashable, Sendable {
    /// Games per completed set (a match tie-break is stored in points, see `superTieBreakSet`).
    public var completedSets: [Score]
    /// Tie-break points for each completed set that was decided by a tie-break.
    public var tieBreakScores: [Int: Score]
    /// Index in `completedSets` of the deciding match tie-break, if one was played.
    public var superTieBreakSet: Int?
    public var games: Score
    /// Raw points in the current game or tie-break.
    public var points: Score
    public var inTieBreak: Bool
    public var isSuperTieBreak: Bool
    public var setsWon: Score
    public var winner: TeamSide?

    public init() {
        completedSets = []
        tieBreakScores = [:]
        superTieBreakSet = nil
        games = .zero
        points = .zero
        inTieBreak = false
        isSuperTieBreak = false
        setsWon = .zero
        winner = nil
    }

    public var isDecided: Bool { winner != nil }

    /// Games won in total; a match tie-break counts as one game for its winner. Used as
    /// the "points" figure in standings for games/sets tournaments.
    public var totalGames: Score {
        var total = games
        for (index, set) in completedSets.enumerated() {
            if index == superTieBreakSet {
                if let w = set.winner { total[w] += 1 }
            } else {
                total.a += set.a
                total.b += set.b
            }
        }
        return total
    }

    /// Applies one rally won by `side`. Points after the match is decided are ignored
    /// (the scoring engine rejects them before they get here).
    public mutating func pointWon(by side: TeamSide, rules: SetsRules) {
        guard winner == nil else { return }
        points[side] += 1
        if inTieBreak {
            let target = isSuperTieBreak ? SetsRules.superTieBreakPoints : rules.tieBreakPoints
            if points[side] >= target && points[side] - points[side.opposite] >= 2 {
                if isSuperTieBreak {
                    superTieBreakSet = completedSets.count
                    closeSet(winner: side, recorded: points, rules: rules)
                } else {
                    tieBreakScores[completedSets.count] = points
                    games[side] += 1
                    closeSet(winner: side, recorded: games, rules: rules)
                }
            }
            return
        }
        let mine = points[side], theirs = points[side.opposite]
        let wonGame = rules.goldenPoint ? mine >= 4 : (mine >= 4 && mine - theirs >= 2)
        if wonGame {
            points = .zero
            games[side] += 1
            checkSet(after: side, rules: rules)
        } else if !rules.goldenPoint && mine == theirs && mine > 3 {
            // Back to deuce: keep numbers small.
            points = Score(a: 3, b: 3)
        }
    }

    private mutating func checkSet(after side: TeamSide, rules: SetsRules) {
        let n = rules.gamesPerSet
        let mine = games[side], theirs = games[side.opposite]
        if mine >= n && mine - theirs >= 2 {
            closeSet(winner: side, recorded: games, rules: rules)
        } else if rules.tieBreak && games.a == n && games.b == n {
            inTieBreak = true
        }
    }

    private mutating func closeSet(winner side: TeamSide, recorded: Score, rules: SetsRules) {
        completedSets.append(recorded)
        setsWon[side] += 1
        games = .zero
        points = .zero
        inTieBreak = false
        isSuperTieBreak = false
        if setsWon[side] >= rules.setsToWin {
            winner = side
        } else if rules.superTieBreakDecider && rules.setsToWin > 1
                    && setsWon.a == rules.setsToWin - 1 && setsWon.b == rules.setsToWin - 1 {
            inTieBreak = true
            isSuperTieBreak = true
        }
    }

    // MARK: Manual results

    /// Builds the final state from entered set scores (e.g. [6-4, 3-6, 10-8]). Returns nil
    /// when the scores are not a legal, complete match under `rules`.
    public static func fromFinalSets(_ sets: [Score], rules: SetsRules) -> SetsState? {
        guard !sets.isEmpty else { return nil }
        var state = SetsState()
        for (index, set) in sets.enumerated() {
            guard state.winner == nil, let setWinner = set.winner else { return nil }
            let deciding = state.isSuperTieBreak
            guard rules.isLegalSetScore(set, isSuperTieBreak: deciding) else { return nil }
            if deciding { state.superTieBreakSet = index }
            state.closeSet(winner: setWinner, recorded: set, rules: rules)
        }
        return state.winner == nil ? nil : state
    }

    // MARK: Display

    /// "0", "15", "30", "40", "Ad", or the tie-break count.
    public func pointLabel(_ side: TeamSide, rules: SetsRules) -> String {
        if inTieBreak { return "\(points[side])" }
        let mine = points[side], theirs = points[side.opposite]
        if !rules.goldenPoint && mine >= 3 && theirs >= 3 {
            if mine > theirs { return "Ad" }
            if mine < theirs { return "40" }
            return "40"
        }
        switch mine {
        case 0: return "0"
        case 1: return "15"
        case 2: return "30"
        default: return "40"
        }
    }

    /// Short description of the current game situation, e.g. "Deuce", "Golden point",
    /// "Tie-break", "Match tie-break".
    public func situation(rules: SetsRules) -> String? {
        if winner != nil { return nil }
        if isSuperTieBreak { return "Match tie-break" }
        if inTieBreak { return "Tie-break" }
        if points.a >= 3 && points.b >= 3 {
            if rules.goldenPoint { return "Golden point" }
            return points.a == points.b ? "Deuce" : "Advantage"
        }
        return nil
    }

    /// "6-4 3-6 [10-8]" style summary of completed sets, plus the current set in progress.
    public func summary(includeCurrent: Bool = true) -> String {
        var parts: [String] = []
        for (index, set) in completedSets.enumerated() {
            if index == superTieBreakSet {
                parts.append("[\(set.a)-\(set.b)]")
            } else if let tb = tieBreakScores[index] {
                parts.append("\(set.a)-\(set.b)(\(min(tb.a, tb.b)))")
            } else {
                parts.append("\(set.a)-\(set.b)")
            }
        }
        if includeCurrent && winner == nil && (games != .zero || points != .zero || !completedSets.isEmpty) {
            parts.append(isSuperTieBreak ? "[\(points.a)-\(points.b)]" : "\(games.a)-\(games.b)")
        }
        return parts.joined(separator: " ")
    }
}
