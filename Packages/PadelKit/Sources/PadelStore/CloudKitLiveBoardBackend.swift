#if canImport(CloudKit)
@preconcurrency import CloudKit
import Foundation
import PadelCore

/// Spectator boards in CloudKit's public database: one `PadelLiveBoard` record per
/// shared board, named by its random token, with the board as compact JSON (`payload`)
/// and when it was published (`updatedAt`). The web page (`docs/live`) reads the record
/// anonymously with CloudKit JS; only the organiser who created it can change or delete it.
///
/// Every CloudKit object stays inside these methods; only value types cross over.
public struct CloudKitLiveBoardBackend: LiveBoardBackend {
    static let recordType = "PadelLiveBoard"

    enum Field {
        static let payload = "payload"
        static let updatedAt = "updatedAt"
    }

    public let containerIdentifier: String

    public init(containerIdentifier: String = CloudKitSharedBackend.defaultContainerIdentifier) {
        self.containerIdentifier = containerIdentifier
    }

    private var database: CKDatabase { CKContainer(identifier: containerIdentifier).publicCloudDatabase }

    public func publish(token: String, payload: String, updatedAt: Date) async throws {
        do {
            let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: token))
            record[Field.payload] = payload as CKRecordValue
            record[Field.updatedAt] = updatedAt as CKRecordValue
            let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            _ = try result.saveResults[record.recordID]?.get()
        } catch {
            throw CloudKitSharedBackend.translate(error)
        }
    }

    public func remove(token: String) async throws {
        let recordID = CKRecord.ID(recordName: token)
        do {
            let result = try await database.modifyRecords(saving: [], deleting: [recordID], savePolicy: .allKeys)
            _ = try result.deleteResults[recordID]?.get()
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone.
        } catch {
            throw CloudKitSharedBackend.translate(error)
        }
    }
}
#endif
