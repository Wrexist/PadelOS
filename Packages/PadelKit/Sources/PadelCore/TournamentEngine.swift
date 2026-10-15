import Foundation

/// Everything an engine operation needs from the outside world. Injected so tests are
/// deterministic and so the domain never reads clocks or random UUIDs itself.
public struct EngineContext: Sendable {
    public var now: Date
    public var deviceID: DeviceID
    public var ids: IdentifierGenerating

    public init(now: Date, deviceID: DeviceID, ids: IdentifierGenerating = RandomIdentifierGenerator()) {
        self.now = now
        self.deviceID = deviceID
        self.ids = ids
    }
}

public enum TournamentError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidConfiguration([ValidationIssue])
    case scoring(ScoreRejection)
    case unknownMatch
    case unknownPlayer
    case tournamentCompleted
    case notAllowed(String)

    public var description: String {
        switch self {
        case .invalidConfiguration(let issues): issues.first(where: { $0.severity == .error })?.message ?? L10n.string("The configuration is not valid.")
        case .scoring(let rejection): rejection.description
        case .unknownMatch: L10n.string("The match no longer exists.")
        case .unknownPlayer: L10n.string("The player no longer exists.")
        case .tournamentCompleted: L10n.string("The tournament is finished. Reopen it to make changes.")
        case .notAllowed(let reason): reason
        }
    }
}

/// Result of applying events received from another device.
public struct RemoteApplyReport: Sendable, Equatable {
    public var applied: [EventID] = []
    public var duplicates: [EventID] = []
    public var conflicts: [ScoreConflict] = []

    public init() {}

    public var processedIDs: [EventID] { applied + duplicates + conflicts.map(\.id) }
}

// MARK: - Creation

extension Tournament {
    /// Validates the draft and creates a tournament with its initial schedule.
    public static func create(from draft: TournamentDraft, id: TournamentID? = nil, context: EngineContext) throws(TournamentError) -> Tournament {
        let errors = ConfigurationValidator.errors(draft)
        guard errors.isEmpty else { throw .invalidConfiguration(errors) }
        let format = draft.configuration.format
        let players = draft.players.map { player in
            Player(id: player.id, name: player.name.trimmingCharacters(in: .whitespacesAndNewlines), group: format.usesGroups ? player.group : nil)
        }
        var tournament = Tournament(
            id: id ?? TournamentID(context.ids.next()),
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: context.now,
            configuration: draft.configuration,
            players: players,
            teams: format.usesTeams ? draft.teams : []
        )
        tournament.buildSchedule(ids: context.ids)
        return tournament
    }

    /// Number of rounds that are scheduled without looking at standings.
    var regularRoundCount: Int {
        configuration.roundCount - (configuration.standingsBasedFinalRound ? 1 : 0)
    }

    /// True for rounds that must be generated from standings once earlier rounds finish.
    func isStandingsBased(_ number: Int) -> Bool {
        if number > configuration.roundCount { return true } // knockout stage
        if configuration.standingsBasedFinalRound && number == configuration.roundCount { return true }
        return !configuration.format.hasPrecomputedSchedule && number > 1
    }

    mutating func buildSchedule(ids: IdentifierGenerating) {
        rounds = []
        if configuration.format.hasPrecomputedSchedule {
            let planned = planRegularRounds(startNumber: 1, count: regularRoundCount, existing: [])
            rounds = planned.map { $0.materialize(ids: ids) }
        }
        reconcileRounds(ids: ids, correctedRound: nil)
    }

    func planRegularRounds(startNumber: Int, count: Int, existing: [Round]) -> [PlannedRound] {
        guard count > 0 else { return [] }
        let seed = configuration.seed
        switch configuration.format {
        case .americano:
            return AmericanoScheduler.generate(players: activePlayers, isMixed: false, courts: configuration.courtCount, existing: existing, startNumber: startNumber, count: count, seed: seed)
        case .mixedAmericano:
            return AmericanoScheduler.generate(players: activePlayers, isMixed: true, courts: configuration.courtCount, existing: existing, startNumber: startNumber, count: count, seed: seed)
        case .teamAmericano:
            return TeamScheduler.generate(teams: activeTeams, courts: configuration.courtCount, existing: existing, startNumber: startNumber, count: count, seed: seed)
        case .mexicano, .mixicano, .teamMexicano, .swiss, .kingOfTheCourt:
            return []
        }
    }

    /// Keeps standings-based rounds consistent with results:
    /// 1. An unstarted standings-based round is removed when an earlier round is no longer
    ///    complete, or when a result in an earlier round was corrected.
    /// 2. When every existing round is complete, the next standings-based round is created.
    /// Rounds that have started are never removed or rewritten.
    mutating func reconcileRounds(ids: IdentifierGenerating, correctedRound: Int?) {
        // A guest's copy follows the organiser's rounds; generating its own would create
        // a competing draw.
        guard !isGuest else { return }
        while let last = rounds.last, !last.hasStarted, isStandingsBased(last.number) {
            let earlierComplete = rounds.dropLast().allSatisfy(\.isCompleted)
            let affected = correctedRound.map { $0 < last.number } ?? false
            guard !earlierComplete || affected else { break }
            rounds.removeLast()
        }
        guard status == .active else { return }
        while rounds.count < configuration.totalRoundCount, rounds.allSatisfy(\.isCompleted) {
            let number = rounds.count + 1
            guard let planned = planStandingsRound(number) else { break }
            rounds.append(planned.materialize(ids: ids))
        }
    }

    /// Plans round `number` when it is a lazily generated round (standings-driven formats
    /// and the optional final round). Returns nil for rounds of a precomputed schedule.
    func planStandingsRound(_ number: Int) -> PlannedRound? {
        if number > configuration.roundCount { return planKnockoutRound(number) }
        let format = configuration.format
        let isFinal = configuration.standingsBasedFinalRound && number == configuration.roundCount
        let standings = number > 1 ? StandingsCalculator.compute(self, throughRound: number - 1) : nil
        let activePlayerIDs = activePlayers.map(\.id)
        let activeTeamIDs = activeTeams.map(\.id)
        if isFinal, let standings {
            if format.isIndividual {
                let active = Set(activePlayerIDs)
                let ranking = standings.playerRanking.filter(active.contains)
                return FinalRoundScheduler.individual(ranking: ranking, players: players, isMixed: format.usesGroups, courts: configuration.courtCount, number: number, pattern: configuration.mexicanoPattern)
            }
            let active = Set(activeTeamIDs)
            return FinalRoundScheduler.team(ranking: standings.teamRanking.filter(active.contains), teams: teams, courts: configuration.courtCount, number: number)
        }
        guard !format.hasPrecomputedSchedule else { return nil }

        /// Round 1 order (seeded draw or list order), later rounds by standings.
        func order<ID: Hashable>(_ ids: [ID], ranked: [ID]?) -> [ID] {
            if let ranked {
                let active = Set(ids)
                return ranked.filter(active.contains)
            }
            switch configuration.mexicanoFirstRound {
            case .listOrder: return ids
            case .random:
                var random = SeededGenerator(seed: configuration.seed, streams: 5)
                return random.shuffled(ids)
            }
        }
        let history = PlayerHistory.players(from: rounds)
        let courts = configuration.courtCount
        let seed = configuration.seed
        switch format {
        case .mexicano:
            let ranking = order(activePlayerIDs, ranked: standings?.playerRanking)
            return MexicanoScheduler.planRound(ranking: ranking, courts: courts, number: number, history: history, pattern: configuration.mexicanoPattern, seed: seed)
        case .mixicano:
            let ranking = order(activePlayerIDs, ranked: standings?.playerRanking)
            let groupA = ranking.filter { player($0)?.group == .a }
            let groupB = ranking.filter { player($0)?.group == .b }
            return MixicanoScheduler.planRound(rankingA: groupA, rankingB: groupB, courts: courts, number: number, history: history, seed: seed)
        case .teamMexicano, .swiss:
            let ranking = order(activeTeamIDs, ranked: standings?.teamRanking)
            return TeamMexicanoScheduler.planRound(ranking: ranking, teams: teams, courts: courts, number: number, history: TeamHistory.teams(from: rounds), seed: seed)
        case .kingOfTheCourt:
            let ranking = order(activePlayerIDs, ranked: standings?.playerRanking)
            return KingOfTheCourtScheduler.planRound(ranking: ranking, previous: number > 1 ? rounds.last : nil, courts: courts, number: number, history: history, seed: seed)
        case .americano, .mixedAmericano, .teamAmericano:
            return nil
        }
    }

    /// Replaces every round that has not started with a fresh plan based on the current
    /// participants and settings. Started rounds are kept exactly as they are.
    mutating func regenerateFutureRounds(ids: IdentifierGenerating) {
        guard !isGuest else { return }
        let keepCount = (rounds.lastIndex(where: \.hasStarted).map { $0 + 1 }) ?? 0
        rounds = Array(rounds.prefix(keepCount))
        if configuration.format.hasPrecomputedSchedule && keepCount < regularRoundCount {
            let planned = planRegularRounds(startNumber: keepCount + 1, count: regularRoundCount - keepCount, existing: rounds)
            rounds += planned.map { $0.materialize(ids: ids) }
        }
        reconcileRounds(ids: ids, correctedRound: nil)
    }

    mutating func touch(_ now: Date) {
        revision += 1
        updatedAt = now
    }
}

// MARK: - Scoring

extension Tournament {
    private func requireActive() throws(TournamentError) {
        guard status == .active else { throw .tournamentCompleted }
    }

    private func makeEvent(_ kind: ScoreEvent.Kind, for match: Match, context: EngineContext) -> ScoreEvent {
        ScoreEvent(
            id: EventID(context.ids.next()),
            tournamentID: id,
            matchID: match.id,
            kind: kind,
            previousScore: match.score,
            resultingScore: match.score,
            timestamp: context.now,
            deviceID: context.deviceID,
            deviceSequence: revision + 1,
            baseRevision: match.log.count
        )
    }

    /// Applies one locally created event. The tournament is unchanged if it throws.
    @discardableResult
    private mutating func applyLocal(_ kind: ScoreEvent.Kind, to matchID: MatchID, context: EngineContext, correctedRound: Int? = nil) throws(TournamentError) -> ScoreEvent {
        try requireActive()
        guard let path = indexPath(of: matchID) else { throw .unknownMatch }
        var match = rounds[path.round].matches[path.match]
        let event = makeEvent(kind, for: match, context: context)
        if let rejection = knockoutRejection(kind, on: match) { throw .scoring(rejection) }
        switch ScoringEngine.apply(event, to: &match, rule: scoringRule(for: match)) {
        case .applied, .duplicate: break
        case .rejected(let reason): throw .scoring(reason)
        }
        rounds[path.round].matches[path.match] = match
        reconcileRounds(ids: context.ids, correctedRound: correctedRound)
        touch(context.now)
        return match.log.last ?? event
    }

    @discardableResult
    public mutating func recordPoint(for side: TeamSide, in matchID: MatchID, context: EngineContext) throws(TournamentError) -> ScoreEvent {
        try applyLocal(.point(side), to: matchID, context: context)
    }

    /// Undoes the most recent point or score change of the match.
    @discardableResult
    public mutating func undoLastScoreChange(in matchID: MatchID, context: EngineContext) throws(TournamentError) -> ScoreEvent {
        guard let match = match(matchID) else { throw .unknownMatch }
        guard let target = ScoringEngine.lastUndoableEvent(in: match) else {
            throw .scoring(match.isCompleted ? .matchCompleted : .nothingToUndo)
        }
        return try applyLocal(.undo(target.id), to: matchID, context: context)
    }

    public mutating func finishMatch(_ matchID: MatchID, context: EngineContext) throws(TournamentError) {
        try applyLocal(.finish, to: matchID, context: context)
    }

    public mutating func reopenMatch(_ matchID: MatchID, context: EngineContext) throws(TournamentError) {
        try applyLocal(.reopen, to: matchID, context: context)
    }

    /// Sets the score of an unfinished match without finishing it.
    public mutating func setScore(_ score: Score, in matchID: MatchID, context: EngineContext) throws(TournamentError) {
        try applyLocal(.setScore(score), to: matchID, context: context)
    }

    /// Enters or corrects a final result in one atomic step (reopen if needed, set, finish).
    /// If later standings-based rounds have not started they are rebuilt from the
    /// corrected standings; rounds already started are never changed.
    /// Enters or corrects a games/sets result (e.g. [6-4, 3-6, 10-8]) atomically.
    public mutating func enterSetsResult(_ sets: [Score], for matchID: MatchID, context: EngineContext) throws(TournamentError) {
        try requireActive()
        guard let path = indexPath(of: matchID) else { throw .unknownMatch }
        var match = rounds[path.round].matches[path.match]
        if let rejection = ScoringEngine.validateSets(sets, rule: scoringRule(for: match)) { throw .scoring(rejection) }
        let wasCompleted = match.isCompleted
        if wasCompleted, let current = match.sets, current.completedSets == sets { return }
        var steps: [ScoreEvent.Kind] = []
        if wasCompleted { steps.append(.reopen) }
        steps.append(.setSets(sets))
        steps.append(.finish)
        for kind in steps {
            let event = makeEvent(kind, for: match, context: context)
            if case .rejected(let reason) = ScoringEngine.apply(event, to: &match, rule: scoringRule(for: match)) {
                throw .scoring(reason)
            }
        }
        rounds[path.round].matches[path.match] = match
        reconcileRounds(ids: context.ids, correctedRound: wasCompleted ? match.roundNumber : nil)
        touch(context.now)
    }

    public mutating func enterResult(_ score: Score, for matchID: MatchID, context: EngineContext) throws(TournamentError) {
        try requireActive()
        guard let path = indexPath(of: matchID) else { throw .unknownMatch }
        var match = rounds[path.round].matches[path.match]
        if let rejection = ScoringEngine.validateFinalScore(score, rule: scoringRule(for: match)) { throw .scoring(rejection) }
        if isKnockout(match) && score.a == score.b { throw .scoring(.drawNotAllowed) }
        let wasCompleted = match.isCompleted
        if wasCompleted && match.score == score { return }
        var steps: [ScoreEvent.Kind] = []
        if wasCompleted { steps.append(.reopen) }
        if match.score != score { steps.append(.setScore(score)) }
        steps.append(.finish)
        for kind in steps {
            let event = makeEvent(kind, for: match, context: context)
            if case .rejected(let reason) = ScoringEngine.apply(event, to: &match, rule: scoringRule(for: match)) {
                throw .scoring(reason)
            }
        }
        rounds[path.round].matches[path.match] = match
        reconcileRounds(ids: context.ids, correctedRound: wasCompleted ? match.roundNumber : nil)
        touch(context.now)
    }

    /// Clears a match back to unplayed (only while it is not finished).
    public mutating func resetMatch(_ matchID: MatchID, context: EngineContext) throws(TournamentError) {
        try setScore(.zero, in: matchID, context: context)
    }

    public mutating func acknowledgeConflicts(in matchID: MatchID, now: Date) {
        guard let path = indexPath(of: matchID) else { return }
        ScoringEngine.acknowledgeConflicts(in: &rounds[path.round].matches[path.match])
        touch(now)
    }

    public mutating func acknowledgeAllConflicts(now: Date) {
        for r in rounds.indices {
            for m in rounds[r].matches.indices where !rounds[r].matches[m].openConflicts.isEmpty {
                ScoringEngine.acknowledgeConflicts(in: &rounds[r].matches[m])
            }
        }
        for index in orphanedConflicts.indices { orphanedConflicts[index].isAcknowledged = true }
        touch(now)
    }

    /// Applies events created on another device (e.g. the watch). Idempotent: events
    /// already seen are reported as duplicates. Events that cannot be applied are kept as
    /// conflicts on their match for the organiser to review. Events are processed in
    /// per-device sequence order.
    @discardableResult
    public mutating func applyRemoteEvents(_ events: [ScoreEvent], context: EngineContext) -> RemoteApplyReport {
        var report = RemoteApplyReport()
        let ordered = events.enumerated().sorted { x, y in
            if x.element.deviceID != y.element.deviceID { return x.element.deviceID < y.element.deviceID }
            if x.element.deviceSequence != y.element.deviceSequence { return x.element.deviceSequence < y.element.deviceSequence }
            return x.offset < y.offset
        }.map(\.element)
        var changed = false
        for event in ordered where event.tournamentID == id {
            guard let path = indexPath(of: event.matchID) else {
                // The match was replaced (e.g. a regenerated round). Keep the event on the
                // tournament so it is visible, rather than dropping it.
                if !orphanedConflicts.contains(where: { $0.id == event.id }) {
                    let conflict = ScoreConflict(event: event, reason: .unknownMatch, recordedAt: context.now)
                    orphanedConflicts.append(conflict)
                    report.conflicts.append(conflict)
                    changed = true
                } else {
                    report.duplicates.append(event.id)
                }
                continue
            }
            var match = rounds[path.round].matches[path.match]
            if match.knownEventIDs.contains(event.id) {
                report.duplicates.append(event.id)
                continue
            }
            let outcome: ApplyOutcome = status == .active
                ? (knockoutRejection(event.kind, on: match).map { ApplyOutcome.rejected($0) } ?? ScoringEngine.apply(event, to: &match, rule: scoringRule(for: match)))
                : .rejected(.tournamentCompleted)
            switch outcome {
            case .applied:
                report.applied.append(event.id)
            case .duplicate:
                report.duplicates.append(event.id)
            case .rejected(let reason):
                ScoringEngine.recordConflict(event, reason: reason, in: &match, at: context.now)
                report.conflicts.append(ScoreConflict(event: event, reason: reason, recordedAt: context.now))
            }
            rounds[path.round].matches[path.match] = match
            changed = changed || outcome != .duplicate
        }
        rememberProcessed(report.processedIDs)
        if changed {
            reconcileRounds(ids: context.ids, correctedRound: nil)
            touch(context.now)
        }
        return report
    }

    mutating func rememberProcessed(_ ids: [EventID]) {
        guard !ids.isEmpty else { return }
        let existing = Set(processedRemoteEventIDs)
        processedRemoteEventIDs.append(contentsOf: ids.filter { !existing.contains($0) })
        if processedRemoteEventIDs.count > Self.processedRemoteEventLimit {
            processedRemoteEventIDs.removeFirst(processedRemoteEventIDs.count - Self.processedRemoteEventLimit)
        }
    }
}

// MARK: - Lifecycle and management

extension Tournament {
    /// Changing the schedule, players or settings is up to the organiser's phone.
    private func requireOrganiser() throws(TournamentError) {
        guard !isGuest else { throw .notAllowed(L10n.string("Only the organiser can change this tournament.")) }
    }

    public mutating func rename(_ newName: String, now: Date) throws(TournamentError) {
        try requireOrganiser()
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .notAllowed(L10n.string("Give the tournament a name.")) }
        name = trimmed
        touch(now)
    }

    /// Number of rounds that have at least one started match.
    public var startedRoundCount: Int { rounds.filter(\.hasStarted).count }

    /// Changes settings that are safe to change mid-tournament. Played rounds are kept;
    /// rounds that have not started are rebuilt. The points rule can only change before
    /// any match has started, because finished results would no longer be valid.
    public mutating func updateSettings(
        courtCount: Int? = nil,
        roundCount: Int? = nil,
        scoring: ScoringRule? = nil,
        restCompensation: RestCompensation? = nil,
        standingsBasedFinalRound: Bool? = nil,
        playoff: PlayoffSize? = nil,
        context: EngineContext
    ) throws(TournamentError) {
        try requireOrganiser()
        try requireActive()
        var newConfig = configuration
        if let courtCount { newConfig.courtCount = courtCount }
        if let roundCount { newConfig.roundCount = roundCount }
        if let restCompensation { newConfig.restCompensation = restCompensation }
        if let standingsBasedFinalRound { newConfig.standingsBasedFinalRound = standingsBasedFinalRound }
        if let playoff, playoff != configuration.playoff {
            guard !rounds.contains(where: { $0.kind == .knockout && $0.hasStarted }) else {
                throw .notAllowed(L10n.string("The playoffs have already started."))
            }
            newConfig.playoff = playoff
        }
        if let scoring, scoring != configuration.scoring {
            guard !hasAnyResult else {
                throw .notAllowed(L10n.string("Points per match can only be changed before the first point is played."))
            }
            newConfig.scoring = scoring
        }
        let started = startedRoundCount
        if newConfig.roundCount < max(1, started) {
            throw .notAllowed(L10n.format("Rounds already played: %lld. The tournament cannot have fewer rounds than that.", started))
        }
        if newConfig.standingsBasedFinalRound != configuration.standingsBasedFinalRound,
           rounds.contains(where: { $0.kind == .final && $0.hasStarted }) {
            throw .notAllowed(L10n.string("The final round has already started."))
        }
        if newConfig.standingsBasedFinalRound && newConfig.roundCount <= started {
            throw .notAllowed(L10n.string("A final round needs at least one unplayed round."))
        }
        let draft = TournamentDraft(name: name, configuration: newConfig, players: activePlayers, teams: activeTeams)
        let errors = ConfigurationValidator.errors(draft)
        guard errors.isEmpty else { throw .invalidConfiguration(errors) }
        let scheduleChanged = newConfig.courtCount != configuration.courtCount
            || newConfig.roundCount != configuration.roundCount
            || newConfig.standingsBasedFinalRound != configuration.standingsBasedFinalRound
            || newConfig.playoff != configuration.playoff
            || newConfig.scoring != configuration.scoring
        configuration = newConfig
        if scheduleChanged { regenerateFutureRounds(ids: context.ids) }
        touch(context.now)
    }

    /// Removes a player from all rounds that have not started. Results already played are
    /// kept and the player stays in the standings, marked as withdrawn.
    public mutating func withdrawPlayer(_ playerID: PlayerID, context: EngineContext) throws(TournamentError) {
        try requireOrganiser()
        try requireActive()
        guard configuration.format.isIndividual else { throw .notAllowed(L10n.string("With fixed teams, withdraw the whole team.")) }
        guard let player = player(playerID), !withdrawnPlayerIDs.contains(playerID) else { throw .unknownPlayer }
        let remaining = activePlayers.filter { $0.id != playerID }
        if configuration.format.usesGroups {
            let count = remaining.filter { $0.group == player.group }.count
            guard count >= 2 else {
                throw .notAllowed(L10n.format("Each group needs at least 2 players, so %@ cannot withdraw.", player.name))
            }
        } else if remaining.count < 4 {
            throw .notAllowed(L10n.string("At least 4 players must remain."))
        }
        withdrawnPlayerIDs.append(playerID)
        regenerateFutureRounds(ids: context.ids)
        touch(context.now)
    }

    public mutating func withdrawTeam(_ teamID: TeamID, context: EngineContext) throws(TournamentError) {
        try requireOrganiser()
        try requireActive()
        guard configuration.format.usesTeams else { throw .notAllowed(L10n.string("Only fixed teams can be withdrawn.")) }
        guard team(teamID) != nil, !withdrawnTeamIDs.contains(teamID) else { throw .unknownPlayer }
        guard activeTeams.count > 2 else { throw .notAllowed(L10n.string("At least 2 teams must remain.")) }
        withdrawnTeamIDs.append(teamID)
        regenerateFutureRounds(ids: context.ids)
        touch(context.now)
    }

    /// Adds a player to all rounds that have not started.
    @discardableResult
    public mutating func addPlayer(name: String, group: PlayerGroup? = nil, context: EngineContext) throws(TournamentError) -> Player {
        try requireOrganiser()
        try requireActive()
        guard configuration.format.isIndividual else { throw .notAllowed(L10n.string("With fixed teams, add a whole team.")) }
        let player = Player(id: PlayerID(context.ids.next()), name: name.trimmingCharacters(in: .whitespacesAndNewlines), group: configuration.format.usesGroups ? group : nil)
        let draft = TournamentDraft(name: self.name, configuration: configuration, players: activePlayers + [player])
        let errors = ConfigurationValidator.errors(draft)
        guard errors.isEmpty else { throw .invalidConfiguration(errors) }
        players.append(player)
        regenerateFutureRounds(ids: context.ids)
        touch(context.now)
        return player
    }

    @discardableResult
    public mutating func addTeam(name: String, playerNames: [String], context: EngineContext) throws(TournamentError) -> Team {
        try requireOrganiser()
        try requireActive()
        guard configuration.format.usesTeams else { throw .notAllowed(L10n.string("Teams are only used in fixed-team formats.")) }
        let newPlayers = playerNames.map { Player(id: PlayerID(context.ids.next()), name: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let team = Team(id: TeamID(context.ids.next()), name: name.trimmingCharacters(in: .whitespacesAndNewlines), playerIDs: newPlayers.map(\.id))
        let allPlayers = activeTeams.flatMap(\.playerIDs).compactMap { self.player($0) } + newPlayers
        let draft = TournamentDraft(name: self.name, configuration: configuration, players: allPlayers, teams: activeTeams + [team])
        let errors = ConfigurationValidator.errors(draft)
        guard errors.isEmpty else { throw .invalidConfiguration(errors) }
        players += newPlayers
        teams.append(team)
        regenerateFutureRounds(ids: context.ids)
        touch(context.now)
        return team
    }

    /// Clears every result and rebuilds the schedule. Withdrawn players are removed.
    /// Pass a new seed to get a different draw.
    public mutating func restart(newSeed: UInt64? = nil, context: EngineContext) {
        guard !isGuest else { return }
        players.removeAll { withdrawnPlayerIDs.contains($0.id) }
        teams.removeAll { withdrawnTeamIDs.contains($0.id) }
        withdrawnPlayerIDs = []
        withdrawnTeamIDs = []
        orphanedConflicts = []
        if let newSeed { configuration.seed = newSeed }
        status = .active
        completedAt = nil
        buildSchedule(ids: context.ids)
        touch(context.now)
    }

    public mutating func finish(now: Date) {
        guard status == .active, !isGuest else { return }
        status = .completed
        completedAt = now
        touch(now)
    }

    public mutating func reopen(context: EngineContext) {
        guard status == .completed, !isGuest else { return }
        status = .active
        completedAt = nil
        reconcileRounds(ids: context.ids, correctedRound: nil)
        touch(context.now)
    }

    /// Rebuilds cached match state from logs. Returns the number of repaired matches.
    @discardableResult
    public mutating func repairCaches() -> Int {
        var repaired = 0
        for r in rounds.indices {
            for m in rounds[r].matches.indices where ScoringEngine.repairCache(&rounds[r].matches[m], rule: scoringRule(for: rounds[r].matches[m])) {
                repaired += 1
            }
        }
        return repaired
    }
}
