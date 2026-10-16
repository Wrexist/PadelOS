import Foundation

/// How a tournament is shared between phones.
///
/// The organiser's phone (host) stays the authority, exactly like the iPhone is for its
/// watch: it applies everyone's score events, generates rounds and publishes its state.
/// A guest's copy is the host's latest state with the guest's own unconfirmed events
/// replayed on top, so the guest (and its watch) can score offline.
public struct SharingInfo: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable, Hashable {
        case host
        case guest
    }

    public var role: Role
    /// Where the shared copy lives (a CloudKit record zone). Opaque to the domain.
    public var zoneName: String
    public var zoneOwner: String
    /// Host: revision last published. Guest: revision of the host state last adopted.
    public var syncedRevision: Int

    public init(role: Role, zoneName: String, zoneOwner: String, syncedRevision: Int = 0) {
        self.role = role
        self.zoneName = zoneName
        self.zoneOwner = zoneOwner
        self.syncedRevision = syncedRevision
    }
}

extension Tournament {
    public var isGuest: Bool { sharing?.role == .guest }
    public var isHost: Bool { sharing?.role == .host }

    /// Marks the tournament as shared (or local again with `nil`). Does not count as a
    /// change to the tournament itself.
    public mutating func setSharing(_ info: SharingInfo?) {
        sharing = info
    }

    /// Host: remembers which revision has been published.
    public mutating func markPublished(revision published: Int) {
        sharing?.syncedRevision = published
    }

    /// A guest copy of the host's state.
    public static func guestCopy(of host: Tournament, zoneName: String, zoneOwner: String) -> Tournament {
        var copy = host
        copy.sharing = SharingInfo(role: .guest, zoneName: zoneName, zoneOwner: zoneOwner, syncedRevision: host.revision)
        // The spectator board belongs to the organiser's phone.
        copy.liveBoardToken = nil
        return copy
    }

    /// Score events held here that `host` has not recorded yet: applied events first
    /// (in each match's log order), then events kept as conflicts.
    public func pendingEvents(notIn host: Tournament) -> [ScoreEvent] {
        var events: [ScoreEvent] = []
        var seen = Set<EventID>()
        func add(_ event: ScoreEvent) {
            guard !host.contains(eventID: event.id), seen.insert(event.id).inserted else { return }
            events.append(event)
        }
        for match in allMatches {
            match.log.forEach(add)
        }
        for match in allMatches {
            match.conflicts.map(\.event).forEach(add)
        }
        orphanedConflicts.map(\.event).forEach(add)
        return events
    }

    public enum RebaseOutcome: Equatable, Sendable {
        /// The host state was adopted; `replayed` local events are still unconfirmed.
        case adopted(replayed: Int)
        /// Not newer than the state already adopted.
        case stale
        /// Only a guest copy can be rebased.
        case notGuest
    }

    /// Guest: adopts a newer host state and replays the local events the host has not
    /// recorded yet. Events that no longer apply are kept as conflicts so they are still
    /// sent to the host (which records them for review) instead of disappearing.
    @discardableResult
    public mutating func rebase(onto host: Tournament, now: Date) -> RebaseOutcome {
        guard let info = sharing, info.role == .guest else { return .notGuest }
        guard host.id == id, host.revision > info.syncedRevision else { return .stale }
        let pending = pendingEvents(notIn: host)
        var result = host
        result.sharing = SharingInfo(role: .guest, zoneName: info.zoneName, zoneOwner: info.zoneOwner, syncedRevision: host.revision)
        result.liveBoardToken = nil
        for event in pending {
            switch result.applyProvisional(event) {
            case .applied, .duplicate:
                break
            case .rejected(let reason):
                result.keepUnapplied(event, reason: reason, at: now)
            }
        }
        // Remote events this copy already processed (from the guest's own watch) stay
        // known, so redelivered batches are recognised as duplicates.
        let pendingIDs = Set(pending.map(\.id))
        result.rememberProcessed(processedRemoteEventIDs.filter { pendingIDs.contains($0) })
        // Events created here are ordered by `revision`, so it must never go backwards.
        result.revision = max(host.revision, revision) + (pending.isEmpty ? 0 : 1)
        self = result
        return .adopted(replayed: pending.count)
    }

    mutating func keepUnapplied(_ event: ScoreEvent, reason: ScoreRejection, at date: Date) {
        if let path = indexPath(of: event.matchID) {
            ScoringEngine.recordConflict(event, reason: reason, in: &rounds[path.round].matches[path.match], at: date)
        } else if !orphanedConflicts.contains(where: { $0.id == event.id }) {
            orphanedConflicts.append(ScoreConflict(event: event, reason: reason, recordedAt: date))
        }
    }
}
