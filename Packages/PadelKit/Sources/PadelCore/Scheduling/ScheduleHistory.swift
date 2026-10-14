import Foundation

/// Counts derived from already scheduled rounds. Scheduling decisions for future rounds
/// are based only on this, so completed rounds are never rewritten.
///
/// Entities are generic: players for individual formats, teams for Team Americano.
public struct PairCounts<Entity: Hashable & Comparable>: Sendable where Entity: Sendable {
    private var storage: [Pair: Int] = [:]

    struct Pair: Hashable, Sendable {
        let low: Entity
        let high: Entity
        init(_ x: Entity, _ y: Entity) {
            if x < y { low = x; high = y } else { low = y; high = x }
        }
    }

    public init() {}

    public subscript(x: Entity, y: Entity) -> Int {
        get { storage[Pair(x, y)] ?? 0 }
        set { storage[Pair(x, y)] = newValue }
    }

    public mutating func increment(_ x: Entity, _ y: Entity) {
        storage[Pair(x, y), default: 0] += 1
    }

    /// Sum over pairs of max(0, count - 1): how many times a pairing happened again.
    public var repeats: Int { storage.values.reduce(0) { $0 + max(0, $1 - 1) } }

    public var sumOfSquares: Int { storage.values.reduce(0) { $0 + $1 * $1 } }

    public var maximum: Int { storage.values.max() ?? 0 }

    public var distinctPairs: Int { storage.values.filter { $0 > 0 }.count }
}

/// Per-entity participation history.
public struct ParticipationHistory<Entity: Hashable & Comparable & Sendable>: Sendable {
    public var partners = PairCounts<Entity>()
    public var opponents = PairCounts<Entity>()
    public var played: [Entity: Int] = [:]
    public var rested: [Entity: Int] = [:]
    /// Most recent round number in which the entity rested.
    public var lastRestRound: [Entity: Int] = [:]
    public var consecutiveRestViolations = 0
    public var roundsRecorded = 0

    public init() {}

    public func playedCount(_ entity: Entity) -> Int { played[entity] ?? 0 }
    public func restCount(_ entity: Entity) -> Int { rested[entity] ?? 0 }

    public func restedInRound(_ entity: Entity, _ round: Int) -> Bool {
        lastRestRound[entity] == round
    }

    /// Records a doubles match (two entities per side). Used for players.
    public mutating func recordDoubles(sideA: [Entity], sideB: [Entity]) {
        for side in [sideA, sideB] where side.count == 2 {
            partners.increment(side[0], side[1])
        }
        for x in sideA { for y in sideB { opponents.increment(x, y) } }
        for entity in sideA + sideB { played[entity, default: 0] += 1 }
    }

    /// Records a match between two single entities (fixed teams).
    public mutating func recordSingle(_ x: Entity, _ y: Entity) {
        opponents.increment(x, y)
        played[x, default: 0] += 1
        played[y, default: 0] += 1
    }

    public mutating func recordRest(_ entities: [Entity], round: Int) {
        for entity in entities {
            if lastRestRound[entity] == round - 1 { consecutiveRestViolations += 1 }
            rested[entity, default: 0] += 1
            lastRestRound[entity] = round
        }
    }
}

public typealias PlayerHistory = ParticipationHistory<PlayerID>
public typealias TeamHistory = ParticipationHistory<TeamID>

extension ParticipationHistory where Entity == PlayerID {
    /// Builds player history from rounds (only the given rounds are considered).
    public static func players(from rounds: [Round]) -> PlayerHistory {
        var history = PlayerHistory()
        for round in rounds {
            for match in round.matches {
                history.recordDoubles(sideA: match.sideA.playerIDs, sideB: match.sideB.playerIDs)
            }
            history.recordRest(round.restingPlayerIDs, round: round.number)
            history.roundsRecorded += 1
        }
        return history
    }
}

extension ParticipationHistory where Entity == TeamID {
    public static func teams(from rounds: [Round]) -> TeamHistory {
        var history = TeamHistory()
        for round in rounds {
            for match in round.matches {
                if let a = match.sideA.teamID, let b = match.sideB.teamID { history.recordSingle(a, b) }
            }
            history.recordRest(round.restingTeamIDs, round: round.number)
            history.roundsRecorded += 1
        }
        return history
    }
}

/// Chooses who rests in a round. Hard rule: those who have played the most matches rest
/// first, which keeps (max played − min played) ≤ 1 for everyone present since round 1
/// (and equivalently balances rests). Using matches played rather than rests means a
/// player who joined late is not asked to sit out again.
/// Soft rules among equals: prefer those who did not rest last round, then those who
/// rested longest ago, then a seeded random order.
enum RestSelector {
    static func select<Entity: Hashable & Comparable & Sendable>(
        count: Int,
        from candidates: [Entity],
        history: ParticipationHistory<Entity>,
        roundNumber: Int,
        random: inout SeededGenerator
    ) -> [Entity] {
        guard count > 0 else { return [] }
        precondition(count <= candidates.count)
        let order = random.shuffled(candidates)
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let sorted = candidates.sorted { x, y in
            let px = history.playedCount(x), py = history.playedCount(y)
            if px != py { return px > py }
            let cx = history.restedInRound(x, roundNumber - 1), cy = history.restedInRound(y, roundNumber - 1)
            if cx != cy { return !cx }
            let lx = history.lastRestRound[x] ?? 0, ly = history.lastRestRound[y] ?? 0
            if lx != ly { return lx < ly }
            return rank[x]! < rank[y]!
        }
        return Array(sorted.prefix(count))
    }
}
