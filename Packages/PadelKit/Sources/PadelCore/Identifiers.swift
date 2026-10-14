import Foundation

/// A strongly typed UUID-backed identifier. Each tag gives a distinct type so a
/// `PlayerID` can never be passed where a `MatchID` is expected.
public struct Identifier<Tag>: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.rawValue = uuid
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: Identifier, rhs: Identifier) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }

    public var description: String { rawValue.uuidString }
}

public enum PlayerTag {}
public enum TeamTag {}
public enum MatchTag {}
public enum TournamentTag {}
public enum EventTag {}
public enum DeviceTag {}

public typealias PlayerID = Identifier<PlayerTag>
public typealias TeamID = Identifier<TeamTag>
public typealias MatchID = Identifier<MatchTag>
public typealias TournamentID = Identifier<TournamentTag>
public typealias EventID = Identifier<EventTag>
public typealias DeviceID = Identifier<DeviceTag>

/// Produces identifiers. Production code uses random UUIDs; tests can inject a
/// deterministic generator so whole tournaments are byte-for-byte reproducible.
public protocol IdentifierGenerating: Sendable {
    func next() -> UUID
}

public struct RandomIdentifierGenerator: IdentifierGenerating {
    public init() {}
    public func next() -> UUID { UUID() }
}

/// Deterministic UUIDs derived from a seed and a counter. Thread-safe.
public final class SequentialIdentifierGenerator: IdentifierGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var counter: UInt64 = 0
    private let seed: UInt64

    public init(seed: UInt64 = 0) {
        self.seed = seed
    }

    public func next() -> UUID {
        lock.lock()
        counter += 1
        let value = counter
        lock.unlock()
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: seed >> (UInt64(i) * 8))
            bytes[8 + i] = UInt8(truncatingIfNeeded: value >> (UInt64(7 - i) * 8))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40 // version 4 layout
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
