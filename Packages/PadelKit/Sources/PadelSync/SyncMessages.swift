import Foundation
import PadelCore

/// Events recorded on the watch and not yet acknowledged by the iPhone. Batches are
/// cumulative: each batch carries every pending event, so a lost or reordered batch is
/// harmless (the phone deduplicates by event ID).
public struct EventBatch: Codable, Hashable, Sendable {
    public var deviceID: DeviceID
    public var events: [ScoreEvent]
    public var sentAt: Date

    public init(deviceID: DeviceID, events: [ScoreEvent], sentAt: Date) {
        self.deviceID = deviceID
        self.events = events
        self.sentAt = sentAt
    }
}

/// The iPhone's authoritative view for the watch. Sent only *after* the phone has saved,
/// so an event ID listed here (or present in a tournament) is durably recorded.
public struct WatchSnapshot: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    /// Snapshots larger than this are trimmed further before sending.
    public static let targetMaximumBytes = 48_000
    public static let maximumAcknowledgements = 400

    public var schemaVersion: Int
    /// Identifies one installation of the iPhone app. A new installation restarts sequences.
    public var phoneInstanceID: UUID
    /// Monotonic per phone installation. Lower numbers are stale.
    public var sequence: Int
    public var generatedAt: Date
    /// Active tournaments, most recently updated first, compacted for the watch.
    public var tournaments: [Tournament]
    /// Remote event IDs the phone has processed (applied or recorded as conflicts).
    public var acknowledgedEventIDs: [EventID]

    public init(phoneInstanceID: UUID, sequence: Int, generatedAt: Date, tournaments: [Tournament], acknowledgedEventIDs: [EventID]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.phoneInstanceID = phoneInstanceID
        self.sequence = sequence
        self.generatedAt = generatedAt
        self.tournaments = tournaments
        self.acknowledgedEventIDs = acknowledgedEventIDs
    }

    /// Builds a snapshot from the phone's tournaments.
    public static func make(
        from all: [Tournament],
        phoneInstanceID: UUID,
        sequence: Int,
        now: Date,
        extraAcknowledged: [EventID] = [],
        maximumTournaments: Int = 3
    ) -> WatchSnapshot {
        let active = all.filter { $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maximumTournaments)
        // Most recent acknowledgements first, bounded so many old tournaments cannot
        // bloat the payload. Events inside the included tournaments are acknowledged by
        // their presence anyway.
        var acknowledged = Array(extraAcknowledged.suffix(maximumAcknowledgements))
        for tournament in all.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let room = maximumAcknowledgements - acknowledged.count
            guard room > 0 else { break }
            acknowledged += tournament.processedRemoteEventIDs.suffix(room)
        }
        var snapshot = WatchSnapshot(
            phoneInstanceID: phoneInstanceID,
            sequence: sequence,
            generatedAt: now,
            tournaments: active.map { $0.compactedForWatch() },
            acknowledgedEventIDs: acknowledged
        )
        // Keep the payload small: drop older tournaments first, never the most recent.
        while snapshot.tournaments.count > 1, (try? SyncCodec.encodedSize(.snapshot(snapshot))) ?? 0 > targetMaximumBytes {
            snapshot.tournaments.removeLast()
        }
        return snapshot
    }

    /// True when `self` should replace `current` (newer or from a new phone installation).
    public func supersedes(_ current: WatchSnapshot?) -> Bool {
        guard let current else { return true }
        if phoneInstanceID != current.phoneInstanceID { return true }
        return sequence > current.sequence
    }

    /// Whether the phone has durably processed an event.
    public func acknowledges(_ id: EventID) -> Bool {
        acknowledgedEventIDs.contains(id) || tournaments.contains { $0.contains(eventID: id) }
    }
}

public enum SyncMessage: Codable, Hashable, Sendable {
    case eventBatch(EventBatch)
    case snapshot(WatchSnapshot)
    case snapshotRequest(DeviceID)
}

/// Encodes messages into WatchConnectivity-compatible dictionaries (property-list types
/// only). The payload is versioned so an older app can recognise and ignore a newer one.
public enum SyncCodec {
    public static let versionKey = "padel.v"
    public static let payloadKey = "padel.payload"
    public static let protocolVersion = 1

    public enum DecodeError: Error, Equatable {
        case notAPadelMessage
        case unsupportedVersion(Int)
        case corrupt
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    public static func encode(_ message: SyncMessage) throws -> [String: Any] {
        [versionKey: protocolVersion, payloadKey: try encoder().encode(message)]
    }

    public static func decode(_ dictionary: [String: Any]) throws(DecodeError) -> SyncMessage {
        guard let version = dictionary[versionKey] as? Int, let data = dictionary[payloadKey] as? Data else {
            throw .notAPadelMessage
        }
        guard version <= protocolVersion else { throw .unsupportedVersion(version) }
        do {
            return try decoder().decode(SyncMessage.self, from: data)
        } catch {
            throw .corrupt
        }
    }

    public static func encodedSize(_ message: SyncMessage) throws -> Int {
        try encoder().encode(message).count
    }
}
