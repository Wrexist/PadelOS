import Foundation

extension Tournament {
    /// The knockout stage of a round, or nil for regular rounds.
    public func knockoutStage(of round: Round) -> KnockoutStage? {
        guard round.kind == .knockout else { return nil }
        let index = round.number - configuration.roundCount - 1
        guard index >= 0 else { return nil }
        return KnockoutStage(rawValue: configuration.playoff.teamCount >> index)
    }

    public func isKnockout(_ match: Match) -> Bool {
        match.roundNumber > configuration.roundCount && configuration.playoff != .none
    }

    /// The rule that applies to one match. Knockout matches need a winner, so an even
    /// points total becomes odd (24 → 25) and cannot end level.
    public func scoringRule(for match: Match) -> ScoringRule {
        guard isKnockout(match) else { return configuration.scoring }
        if case .totalPoints(let total) = configuration.scoring, total % 2 == 0 {
            return .totalPoints(total + 1)
        }
        return configuration.scoring
    }

    /// Extra rule for knockout matches: a timed match cannot be finished level.
    func knockoutRejection(_ kind: ScoreEvent.Kind, on match: Match) -> ScoreRejection? {
        guard isKnockout(match), case .timed = configuration.scoring else { return nil }
        if case .finish = kind, match.score.a == match.score.b { return .drawNotAllowed }
        return nil
    }

    /// Winning side of the completed final, if the playoff has been decided.
    public var playoffChampion: MatchSide? {
        guard configuration.playoff != .none,
              let last = rounds.last, knockoutStage(of: last) == .final,
              let final = last.matches.first, final.isCompleted,
              let winner = ScoringEngine.winner(of: final) else { return nil }
        return final.side(winner)
    }

    /// Runner-up of the completed final.
    public var playoffRunnerUp: MatchSide? {
        guard let champion = playoffChampion, let final = rounds.last?.matches.first else { return nil }
        return final.sideA == champion ? final.sideB : final.sideA
    }

    /// Plans knockout round `number`. The first stage seeds from the standings of the
    /// regular rounds; later stages pair the winners in bracket order.
    func planKnockoutRound(_ number: Int) -> PlannedRound? {
        let stageIndex = number - configuration.roundCount - 1
        guard stageIndex >= 0, stageIndex < configuration.playoff.stageCount else { return nil }
        var sides: [MatchSide]
        if stageIndex == 0 {
            sides = seededSides(count: configuration.playoff.teamCount)
            // Fewer qualified teams than planned (e.g. after withdrawals): use the largest
            // bracket that fits.
            var size = configuration.playoff.teamCount
            while size > sides.count { size /= 2 }
            guard size >= 2 else { return nil }
            sides = Array(sides.prefix(size))
            sides = Self.bracketOrder(size).map { sides[$0] }
        } else {
            guard let previous = rounds.first(where: { $0.number == number - 1 }) else { return nil }
            var winners: [MatchSide] = []
            for match in previous.matches {
                guard match.isCompleted, let winner = ScoringEngine.winner(of: match) else { return nil }
                winners.append(match.side(winner))
            }
            sides = winners
        }
        guard sides.count >= 2 else { return nil }
        var matches: [(MatchSide, MatchSide)] = []
        for index in stride(from: 0, to: sides.count - 1, by: 2) {
            matches.append((sides[index], sides[index + 1]))
        }
        let courts = max(1, configuration.courtCount)
        let playing = Set(matches.flatMap { $0.0.playerIDs + $0.1.playerIDs })
        let playingTeams = Set(matches.compactMap { $0.0.teamID } + matches.compactMap { $0.1.teamID })
        return PlannedRound(
            number: number,
            kind: .knockout,
            matches: matches,
            restingPlayers: activePlayers.map(\.id).filter { !playing.contains($0) },
            restingTeams: activeTeams.map(\.id).filter { !playingTeams.contains($0) },
            courts: matches.indices.map { $0 % courts + 1 }
        )
    }

    /// Qualified pairs in seed order (best first).
    func seededSides(count: Int) -> [MatchSide] {
        let standings = StandingsCalculator.compute(self, throughRound: configuration.roundCount)
        if configuration.format.usesTeams {
            let active = Set(activeTeams.map(\.id))
            return standings.teamRanking.filter(active.contains).prefix(count).compactMap { id in
                team(id).map { MatchSide(playerIDs: $0.playerIDs, teamID: $0.id) }
            }
        }
        let active = Set(activePlayers.map(\.id))
        let ranking = standings.playerRanking.filter(active.contains)
        if configuration.format.usesGroups {
            // Seed i pairs the i-th of one group with the (n+1−i)-th of the other.
            let groupA = ranking.filter { player($0)?.group == .a }
            let groupB = ranking.filter { player($0)?.group == .b }
            let n = min(count, groupA.count, groupB.count)
            return (0..<n).map { MatchSide(playerIDs: [groupA[$0], groupB[n - 1 - $0]]) }
        }
        // Seed i pairs the i-th best with the (2n+1−i)-th best: 1+8, 2+7, 3+6, 4+5.
        let n = min(count, ranking.count / 2)
        return (0..<n).map { MatchSide(playerIDs: [ranking[$0], ranking[2 * n - 1 - $0]]) }
    }

    /// Seed order for a bracket so the top seeds can only meet in the final:
    /// 2 → [1,2]; 4 → [1,4, 2,3]; 8 → [1,8, 4,5, 2,7, 3,6] (zero-based).
    static func bracketOrder(_ size: Int) -> [Int] {
        var order = [0]
        var current = 1
        while current < size {
            current *= 2
            order = order.flatMap { [$0, current - 1 - $0] }
        }
        return order
    }
}
