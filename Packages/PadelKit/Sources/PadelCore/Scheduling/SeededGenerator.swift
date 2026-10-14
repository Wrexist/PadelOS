import Foundation

/// SplitMix64: tiny, fast, and identical on every platform. Swift's system RNG is not
/// seedable, and `Hasher` is randomised per process, so neither may be used where
/// reproducibility matters.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    /// Derives an independent stream for a sub-task, e.g. (tournament seed, round, attempt).
    public init(seed: UInt64, streams: UInt64...) {
        var mixed = seed
        for stream in streams {
            mixed = SeededGenerator.mix(mixed &+ 0x9E37_79B9_7F4A_7C15 &* (stream &+ 1))
        }
        state = mixed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return SeededGenerator.mix(state)
    }

    static func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform integer in `0..<upperBound` without modulo bias.
    public mutating func nextInt(_ upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next(upperBound: UInt64(upperBound)))
    }

    /// Fisher–Yates shuffle that only depends on this generator (stable across Swift versions).
    public mutating func shuffled<T>(_ array: [T]) -> [T] {
        var result = array
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            let j = nextInt(i + 1)
            result.swapAt(i, j)
        }
        return result
    }
}
