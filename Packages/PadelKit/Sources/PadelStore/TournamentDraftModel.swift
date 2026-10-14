import Foundation
import Observation
import PadelCore

/// Editable state behind the "Create Tournament" flow. Pure logic (no UI), so it is
/// unit-tested; the SwiftUI form only binds to it.
@MainActor
@Observable
public final class TournamentDraftModel {
    public enum RoundsMode: String, CaseIterable, Sendable {
        case automatic
        case manual
    }

    public enum ScoringMode: String, CaseIterable, Sendable, Identifiable {
        case points
        case timed
        case sets

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .points: "Points"
            case .timed: "Timed"
            case .sets: "Games & sets"
            }
        }
    }

    public var name: String
    public var format: TournamentFormat
    /// Players in entry order. In Team Americano consecutive pairs form the teams.
    public private(set) var players: [Player]
    public var courtCount: Int
    public var points: Int
    public var scoringMode: ScoringMode
    public var minutes: Int
    public var setsRules: SetsRules
    public var roundsMode: RoundsMode
    public var manualRounds: Int
    public var mixedLabels: MixedGroupLabels
    public var mexicanoPattern: MexicanoPairingPattern
    public var mexicanoFirstRound: MexicanoFirstRound
    public var finalRound: Bool
    public var playoff: PlayoffSize
    public var restCompensation: RestCompensation
    public var seed: UInt64
    /// Group preselected when adding players to a Mixed Americano.
    public var nextGroup: PlayerGroup

    public static let pointOptions = [16, 21, 24, 32]

    public init(settings: AppSettings = AppSettings(), now: Date = Date(), seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        name = Self.defaultName(for: now)
        format = settings.defaultFormat
        players = []
        courtCount = settings.defaultCourtCount
        points = settings.defaultPoints
        scoringMode = .points
        minutes = 12
        setsRules = .oneSet
        roundsMode = .automatic
        manualRounds = 6
        mixedLabels = MixedGroupLabels()
        mexicanoPattern = .oneFourVsTwoThree
        mexicanoFirstRound = .random
        finalRound = false
        playoff = .none
        restCompensation = .none
        self.seed = seed
        nextGroup = .a
    }

    /// Prefilled quick-start Americano using recently entered names.
    public static func quickAmericano(settings: AppSettings, now: Date = Date()) -> TournamentDraftModel {
        let model = TournamentDraftModel(settings: settings, now: now)
        model.format = .americano
        model.name = "Americano \(weekday(now))"
        let count = min(settings.recentPlayerNames.count, settings.defaultCourtCount * 4)
        if count >= 4 {
            for name in settings.recentPlayerNames.prefix(count) { _ = model.addPlayer(named: name) }
        }
        return model
    }

    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func defaultName(for date: Date) -> String {
        "\(weekday(date)) Padel"
    }

    // MARK: Players

    public enum AddResult: Equatable, Sendable {
        case added
        case empty
        case duplicate(String)
        case full
    }

    @discardableResult
    public func addPlayer(named rawName: String, group: PlayerGroup? = nil) -> AddResult {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .empty }
        guard players.count < ConfigurationValidator.maximumPlayers else { return .full }
        if players.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return .duplicate(name) }
        players.append(Player(name: name, group: group ?? nextGroup))
        return .added
    }

    /// Adds names separated by new lines, commas or semicolons. Returns the names skipped
    /// as duplicates so the UI can say so.
    @discardableResult
    public func addMultiple(_ text: String) -> (added: Int, skipped: [String]) {
        let names = text
            .components(separatedBy: CharacterSet(charactersIn: "\n,;"))
            .map { Self.stripListMarker($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        var added = 0
        var skipped: [String] = []
        for name in names {
            switch addPlayer(named: name) {
            case .added: added += 1
            case .duplicate(let duplicate): skipped.append(duplicate)
            case .empty, .full: break
            }
        }
        return (added, skipped)
    }

    /// Removes "1." / "-" / "•" prefixes from pasted lists.
    static func stripListMarker(_ line: String) -> String {
        var result = Substring(line)
        if let first = result.first, "-•*".contains(first) { result = result.dropFirst() }
        let digits = result.prefix { $0.isNumber }
        if !digits.isEmpty, let next = result.dropFirst(digits.count).first, next == "." || next == ")" {
            result = result.dropFirst(digits.count + 1)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    public func removePlayer(_ id: PlayerID) {
        players.removeAll { $0.id == id }
    }

    public func movePlayers(fromOffsets source: IndexSet, toOffset destination: Int) {
        var copy = players
        let moving = source.sorted().map { copy[$0] }
        for index in source.sorted(by: >) { copy.remove(at: index) }
        let adjusted = destination - source.filter { $0 < destination }.count
        copy.insert(contentsOf: moving, at: min(max(0, adjusted), copy.count))
        players = copy
    }

    public func renamePlayer(_ id: PlayerID, to name: String) {
        guard let index = players.firstIndex(where: { $0.id == id }) else { return }
        players[index].name = name
    }

    public func setGroup(_ group: PlayerGroup, for id: PlayerID) {
        guard let index = players.firstIndex(where: { $0.id == id }) else { return }
        players[index].group = group
    }

    public func count(in group: PlayerGroup) -> Int {
        players.filter { $0.group == group }.count
    }

    /// Recently used names that are not in the list yet.
    public func suggestions(from recent: [String], limit: Int = 12) -> [String] {
        recent.filter { name in !players.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Teams (Team Americano)

    /// Teams formed from consecutive pairs; a trailing single player is not a team yet.
    public var teams: [Team] {
        stride(from: 0, to: players.count - 1, by: 2).map { index in
            let a = players[index], b = players[index + 1]
            return Team(id: Self.teamID(a.id, b.id), name: "\(a.name) & \(b.name)", playerIDs: [a.id, b.id])
        }
    }

    /// Deterministic team ID from its players, so the draft is stable between renders.
    static func teamID(_ a: PlayerID, _ b: PlayerID) -> TeamID {
        var bytes = [UInt8](repeating: 0, count: 16)
        let ua = a.rawValue.uuid, ub = b.rawValue.uuid
        let la = withUnsafeBytes(of: ua) { Array($0) }, lb = withUnsafeBytes(of: ub) { Array($0) }
        for i in 0..<16 { bytes[i] = la[i] ^ lb[(i + 7) % 16] }
        return TeamID(UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])))
    }

    public var hasUnpairedPlayer: Bool { format.usesTeams && players.count % 2 == 1 }

    // MARK: Configuration

    /// Kept for convenience: timed matches on/off.
    public var isTimed: Bool {
        get { scoringMode == .timed }
        set { scoringMode = newValue ? .timed : .points }
    }

    public var scoring: ScoringRule {
        switch scoringMode {
        case .points: .totalPoints(points)
        case .timed: .timed(minutes: minutes)
        case .sets: .sets(setsRules)
        }
    }

    public var recommendedRounds: Int {
        RoundPlanner.recommendedRounds(format: format, players: draftPlayers, teamCount: teams.count, courts: courtCount, scoring: scoring)
    }

    public var fullRotationRounds: Int {
        RoundPlanner.fullRotationRounds(format: format, players: draftPlayers, teamCount: teams.count, courts: courtCount)
    }

    public var roundCount: Int {
        roundsMode == .automatic ? recommendedRounds : manualRounds
    }

    public var estimatedMinutes: Int {
        RoundPlanner.estimatedMinutes(rounds: roundCount + playoff.stageCount, scoring: scoring)
    }

    /// Players as they will be saved: groups only for Mixed, unpaired player excluded for teams.
    var draftPlayers: [Player] {
        if format.usesGroups { return players }
        if format.usesTeams {
            return Array(players.prefix(players.count - players.count % 2)).map { Player(id: $0.id, name: $0.name) }
        }
        return players.map { Player(id: $0.id, name: $0.name) }
    }

    public var configuration: TournamentConfiguration {
        TournamentConfiguration(
            format: format,
            courtCount: courtCount,
            roundCount: roundCount,
            scoring: scoring,
            mixedLabels: mixedLabels,
            mexicanoPattern: mexicanoPattern,
            mexicanoFirstRound: mexicanoFirstRound,
            standingsBasedFinalRound: finalRound,
            restCompensation: scoringMode == .points ? restCompensation : .none,
            seed: seed,
            playoff: playoff
        )
    }

    public var draft: TournamentDraft {
        TournamentDraft(name: name, configuration: configuration, players: draftPlayers, teams: format.usesTeams ? teams : [])
    }

    /// Validation issues, including draft-only ones (an unpaired player).
    public var issues: [ValidationIssue] {
        var issues = ConfigurationValidator.validate(draft)
        if hasUnpairedPlayer, let last = players.last {
            issues.insert(ValidationIssue(severity: .error, code: .invalidTeam, message: "\(last.name) has no partner yet.", suggestion: "Add one more player to complete the last team."), at: 0)
        }
        return issues
    }

    public var errors: [ValidationIssue] { issues.filter { $0.severity == .error } }
    public var warnings: [ValidationIssue] { issues.filter { $0.severity == .warning } }
    public var canCreate: Bool { errors.isEmpty }

    /// Minimum participants for the selected format, for the primary button label.
    public var needsMorePlayers: Bool {
        if format.usesGroups { return count(in: .a) < 2 || count(in: .b) < 2 }
        if format.usesTeams { return teams.count < 2 }
        return players.count < 4
    }
}
