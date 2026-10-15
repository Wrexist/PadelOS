import Foundation

/// Arranges 4·m active players into m doubles matches for one round.
///
/// Positions `4j ..< 4j+4` form match j; positions (4j, 4j+1) are team A and
/// (4j+2, 4j+3) are team B. For mixed rounds, even positions hold group-A players and odd
/// positions group-B players, so every team has exactly one player from each group; the
/// search only swaps positions of equal parity, which preserves that hard constraint.
///
/// Objective (lower is better), from the documented scheduling priorities:
///   partnerWeight · c²  for each partnership, where c = times already partnered
///   opponentWeight · c² for each of the four opposing pairs, c = times already opposed
/// Squared counts favour spreading repeats evenly instead of concentrating them.
///
/// Search: steepest-descent pair swaps from several seeded random starts. This is a
/// heuristic: it is not guaranteed globally optimal, which is why schedule quality is
/// measured by tests (`ScheduleMetrics`).
struct DoublesOptimizer {
    static let partnerWeight = 100
    static let opponentWeight = 8

    let partnerCounts: [[Int]]
    let opponentCounts: [[Int]]
    let isMixed: Bool

    /// - Parameters:
    ///   - players: local entities; for mixed rounds the first half are group A and the
    ///     second half group B (equal sizes).
    init(players: [PlayerID], history: PlayerHistory, isMixed: Bool) {
        let n = players.count
        var partners = Array(repeating: Array(repeating: 0, count: n), count: n)
        var opponents = partners
        for i in 0..<n {
            for j in 0..<n where i != j {
                partners[i][j] = history.partners[players[i], players[j]]
                opponents[i][j] = history.opponents[players[i], players[j]]
            }
        }
        self.partnerCounts = partners
        self.opponentCounts = opponents
        self.isMixed = isMixed
    }

    func matchCost(_ arrangement: [Int], match j: Int) -> Int {
        let p0 = arrangement[4 * j], p1 = arrangement[4 * j + 1]
        let p2 = arrangement[4 * j + 2], p3 = arrangement[4 * j + 3]
        let pa = partnerCounts[p0][p1], pb = partnerCounts[p2][p3]
        var cost = Self.partnerWeight * (pa * pa + pb * pb)
        for x in [p0, p1] {
            for y in [p2, p3] {
                let c = opponentCounts[x][y]
                cost += Self.opponentWeight * c * c
            }
        }
        return cost
    }

    func totalCost(_ arrangement: [Int]) -> Int {
        (0..<(arrangement.count / 4)).reduce(0) { $0 + matchCost(arrangement, match: $1) }
    }

    /// Returns the best arrangement found (indices into the `players` array).
    func optimize(matchCount: Int, restarts: Int, random: inout SeededGenerator) -> (arrangement: [Int], cost: Int) {
        let size = matchCount * 4
        var best: [Int] = []
        var bestCost = Int.max
        for _ in 0..<max(1, restarts) {
            var arrangement = initialArrangement(size: size, random: &random)
            var cost = totalCost(arrangement)
            improve(&arrangement, cost: &cost)
            if cost < bestCost {
                best = arrangement
                bestCost = cost
                if bestCost == 0 { break }
            }
        }
        return (best, bestCost)
    }

    private func initialArrangement(size: Int, random: inout SeededGenerator) -> [Int] {
        if isMixed {
            let half = size / 2
            let groupA = random.shuffled(Array(0..<half))
            let groupB = random.shuffled(Array(half..<size))
            var result: [Int] = []
            result.reserveCapacity(size)
            for k in 0..<half {
                result.append(groupA[k])
                result.append(groupB[k])
            }
            return result
        }
        return random.shuffled(Array(0..<size))
    }

    private func improve(_ arrangement: inout [Int], cost: inout Int) {
        let size = arrangement.count
        var improved = true
        while improved {
            improved = false
            var bestDelta = 0
            var bestSwap: (Int, Int)?
            for i in 0..<size {
                for j in (i + 1)..<size {
                    if isMixed && (i % 2 != j % 2) { continue }
                    let mi = i / 4, mj = j / 4
                    // Swapping partners within the same team changes nothing.
                    if mi == mj && (i % 4) / 2 == (j % 4) / 2 { continue }
                    let before = mi == mj
                        ? matchCost(arrangement, match: mi)
                        : matchCost(arrangement, match: mi) + matchCost(arrangement, match: mj)
                    arrangement.swapAt(i, j)
                    let after = mi == mj
                        ? matchCost(arrangement, match: mi)
                        : matchCost(arrangement, match: mi) + matchCost(arrangement, match: mj)
                    arrangement.swapAt(i, j)
                    let delta = after - before
                    if delta < bestDelta {
                        bestDelta = delta
                        bestSwap = (i, j)
                    }
                }
            }
            if let (i, j) = bestSwap {
                arrangement.swapAt(i, j)
                cost += bestDelta
                improved = true
            }
        }
    }
}
