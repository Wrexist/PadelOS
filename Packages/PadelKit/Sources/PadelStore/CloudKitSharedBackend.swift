#if canImport(CloudKit)
@preconcurrency import CloudKit
import Foundation
import PadelCore

/// Shared tournaments in CloudKit. Each tournament gets its own record zone in the
/// organiser's private database, shared with a zone-wide `CKShare` that anyone with the
/// link can join and write to. The zone holds one `PadelTournament` record (the
/// organiser's state, written only by the organiser) and one `PadelEvent` record per
/// score event that a guest has not seen confirmed yet (written by guests, removed by
/// the organiser once recorded).
///
/// Every CloudKit object stays inside these methods; only value types cross over.
public struct CloudKitSharedBackend: SharedTournamentBackend {
    public static let defaultContainerIdentifier = "iCloud.app.padelos.PadelOS"

    enum RecordType {
        static let tournament = "PadelTournament"
        static let event = "PadelEvent"
    }

    enum Field {
        static let payload = "payload"
        static let revision = "revision"
    }

    static let tournamentRecordName = "tournament"
    /// CloudKit refuses records over 1 MB; a large tournament is about 200 KB.
    static let maximumPayloadBytes = 900_000

    public let containerIdentifier: String

    public init(containerIdentifier: String = Self.defaultContainerIdentifier) {
        self.containerIdentifier = containerIdentifier
    }

    private var container: CKContainer { CKContainer(identifier: containerIdentifier) }

    private func database(for zone: SharedZone) -> CKDatabase {
        zone.isOwnedByThisDevice ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    private func zoneID(_ zone: SharedZone) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zone.name, ownerName: zone.owner)
    }

    // MARK: SharedTournamentBackend

    public func share(_ tournament: Tournament) async throws -> (zone: SharedZone, url: URL) {
        try await requireAccount()
        let zone = SharedZone(name: "tournament-\(tournament.id.rawValue.uuidString)", owner: CKCurrentUserDefaultName, isOwnedByThisDevice: true)
        let id = zoneID(zone)
        let database = container.privateCloudDatabase
        do {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: id)], deleting: [])
            let record = try Self.tournamentRecord(tournament, in: id)
            let share = CKShare(recordZoneID: id)
            share[CKShare.SystemFieldKey.title] = tournament.name as CKRecordValue
            share.publicPermission = .readWrite
            let result = try await database.modifyRecords(saving: [record, share], deleting: [], savePolicy: .allKeys)
            _ = try result.saveResults[record.recordID]?.get()
            let saved = try result.saveResults[share.recordID]?.get() as? CKShare
            guard let url = saved?.url ?? share.url else { throw SharingError.service("The invitation link is not ready yet. Try again.") }
            return (zone, url)
        } catch {
            throw Self.translate(error)
        }
    }

    public func invitationURL(for zone: SharedZone) async throws -> URL? {
        do {
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID(zone))
            let record = try await database(for: zone).record(for: shareID)
            return (record as? CKShare)?.url
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        } catch {
            throw Self.translate(error)
        }
    }

    public func changes(in zone: SharedZone, since token: Data?) async throws -> SharedZoneChanges {
        var changes = SharedZoneChanges()
        var position = token.flatMap(Self.unarchive)
        do {
            var moreComing = true
            while moreComing {
                let result = try await database(for: zone).recordZoneChanges(inZoneWith: zoneID(zone), since: position)
                for (_, modification) in result.modificationResultsByID {
                    guard case .success(let change) = modification else { continue }
                    let record = change.record
                    switch record.recordType {
                    case RecordType.tournament:
                        if let tournament = try? Self.decode(Tournament.self, from: record),
                           tournament.revision > (changes.tournament?.revision ?? -1) {
                            changes.tournament = tournament
                        }
                    case RecordType.event:
                        if let event = try? Self.decode(ScoreEvent.self, from: record) {
                            changes.events.append(event)
                        }
                    default:
                        break
                    }
                }
                position = result.changeToken
                moreComing = result.moreComing
            }
        } catch let error as CKError where error.code == .changeTokenExpired {
            // Start over from the beginning of the zone.
            return try await self.changes(in: zone, since: nil)
        } catch {
            throw Self.translate(error)
        }
        changes.token = position.flatMap(Self.archive)
        return changes
    }

    public func publish(_ tournament: Tournament, in zone: SharedZone) async throws {
        do {
            let record = try Self.tournamentRecord(tournament, in: zoneID(zone))
            let result = try await database(for: zone).modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            _ = try result.saveResults[record.recordID]?.get()
        } catch {
            throw Self.translate(error)
        }
    }

    public func upload(_ events: [ScoreEvent], to zone: SharedZone) async throws -> [EventID] {
        guard !events.isEmpty else { return [] }
        do {
            let id = zoneID(zone)
            let records = try events.map { event in
                let record = CKRecord(recordType: RecordType.event, recordID: CKRecord.ID(recordName: event.id.rawValue.uuidString, zoneID: id))
                record[Field.payload] = try JSONEncoder().encode(event) as CKRecordValue
                return record
            }
            let result = try await database(for: zone).modifyRecords(saving: records, deleting: [], savePolicy: .allKeys, atomically: false)
            var stored: [EventID] = []
            var firstError: Error?
            for (recordID, outcome) in result.saveResults {
                switch outcome {
                case .success:
                    if let eventID = EventID(uuidString: recordID.recordName) { stored.append(eventID) }
                case .failure(let error):
                    firstError = firstError ?? error
                }
            }
            if stored.isEmpty, let firstError { throw firstError }
            return stored
        } catch {
            throw Self.translate(error)
        }
    }

    public func removeEvents(_ ids: [EventID], from zone: SharedZone) async throws {
        guard !ids.isEmpty else { return }
        do {
            let id = zoneID(zone)
            let recordIDs = ids.map { CKRecord.ID(recordName: $0.rawValue.uuidString, zoneID: id) }
            _ = try await database(for: zone).modifyRecords(saving: [], deleting: recordIDs, savePolicy: .allKeys, atomically: false)
        } catch {
            throw Self.translate(error)
        }
    }

    public func removeZone(_ zone: SharedZone) async throws {
        do {
            _ = try await database(for: zone).modifyRecordZones(saving: [], deleting: [zoneID(zone)])
        } catch {
            throw Self.translate(error)
        }
    }

    // MARK: Helpers

    private func requireAccount() async throws {
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            throw Self.translate(error)
        }
        guard status == .available else { throw SharingError.noAccount }
    }

    static func tournamentRecord(_ tournament: Tournament, in zoneID: CKRecordZone.ID) throws -> CKRecord {
        let payload = try JSONEncoder().encode(tournament)
        guard payload.count <= maximumPayloadBytes else { throw SharingError.tooLarge }
        let record = CKRecord(recordType: RecordType.tournament, recordID: CKRecord.ID(recordName: tournamentRecordName, zoneID: zoneID))
        record[Field.payload] = payload as CKRecordValue
        record[Field.revision] = tournament.revision as CKRecordValue
        return record
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from record: CKRecord) throws -> Value {
        guard let data = record[Field.payload] as? Data else { throw SharingError.service("A shared record has no content.") }
        return try JSONDecoder().decode(type, from: data)
    }

    static func archive(_ token: CKServerChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    static func unarchive(_ data: Data) -> CKServerChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    static func translate(_ error: Error) -> Error {
        if error is SharingError { return error }
        guard let error = error as? CKError else { return SharingError.service(error.localizedDescription) }
        switch error.code {
        case .notAuthenticated: return SharingError.noAccount
        case .zoneNotFound, .userDeletedZone: return SharingError.zoneMissing
        case .partialFailure:
            let inner = error.partialErrorsByItemID?.values.compactMap { $0 as? CKError } ?? []
            if inner.contains(where: { $0.code == .zoneNotFound || $0.code == .userDeletedZone }) { return SharingError.zoneMissing }
            return SharingError.service(error.localizedDescription)
        default: return SharingError.service(error.localizedDescription)
        }
    }
}
#endif
