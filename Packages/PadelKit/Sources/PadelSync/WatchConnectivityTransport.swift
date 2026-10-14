#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

/// `SyncTransport` backed by `WCSession`. Delegate callbacks arrive on a background
/// queue; everything is forwarded to the main actor.
///
/// Mapping (see Apple's WatchConnectivity documentation):
/// - `updateLatestState` → `updateApplicationContext(_:)` (latest value wins)
/// - `enqueueDurable` → `transferUserInfo(_:)` (queued, survives app exit)
/// - `sendImmediate` → `sendMessage(_:replyHandler:errorHandler:)` (reachable only)
@MainActor
public final class WatchConnectivityTransport: NSObject, SyncTransport {
    public var onReceive: ((SyncMessage, ((SyncMessage) -> Void)?) -> Void)?
    public var onStateChange: (() -> Void)?
    public private(set) var lastError: String?

    private let session: WCSession?

    public override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
    }

    public var isSupported: Bool { session != nil }

    public var isReachable: Bool {
        guard let session, session.activationState == .activated else { return false }
        return session.isReachable
    }

    public var isActivated: Bool { session?.activationState == .activated }

    #if os(iOS)
    /// Whether a paired watch has the app installed (iPhone only).
    public var isCounterpartAppInstalled: Bool {
        guard let session, session.activationState == .activated else { return false }
        return session.isPaired && session.isWatchAppInstalled
    }
    #else
    public var isCounterpartAppInstalled: Bool { isActivated }
    #endif

    public func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    public func updateLatestState(_ message: SyncMessage) throws {
        guard let session, session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        try session.updateApplicationContext(try SyncCodec.encode(message))
    }

    public func enqueueDurable(_ message: SyncMessage, replacingPending: Bool) {
        guard let session, session.activationState == .activated else { return }
        if replacingPending {
            for transfer in session.outstandingUserInfoTransfers where transfer.isTransferring {
                transfer.cancel()
            }
        }
        do {
            session.transferUserInfo(try SyncCodec.encode(message))
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func sendImmediate(_ message: SyncMessage, reply: ((SyncMessage) -> Void)?, failure: ((Error) -> Void)?) {
        guard let session, session.activationState == .activated, session.isReachable else {
            failure?(WCError(.notReachable))
            return
        }
        let payload: [String: Any]
        do {
            payload = try SyncCodec.encode(message)
        } catch {
            failure?(error)
            return
        }
        if let reply {
            session.sendMessage(payload, replyHandler: { response in
                guard let decoded = try? SyncCodec.decode(response) else { return }
                Task { @MainActor in reply(decoded) }
            }, errorHandler: { error in
                Task { @MainActor in failure?(error) }
            })
        } else {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { error in
                Task { @MainActor in failure?(error) }
            })
        }
    }

    fileprivate func deliver(_ dictionary: [String: Any], reply: (([String: Any]) -> Void)?) {
        guard let message = try? SyncCodec.decode(dictionary) else {
            reply?([:])
            return
        }
        let replyBridge: ((SyncMessage) -> Void)? = reply.map { handler in
            { response in handler((try? SyncCodec.encode(response)) ?? [:]) }
        }
        onReceive?(message, replyBridge)
    }

    /// Re-reads the most recent application context, e.g. at launch.
    public func deliverStoredContext() {
        guard let session, session.activationState == .activated else { return }
        let context = session.receivedApplicationContext
        if !context.isEmpty { deliver(context, reply: nil) }
    }
}

extension WatchConnectivityTransport: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in
            self.lastError = message
            self.deliverStoredContext()
            self.onStateChange?()
        }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.onStateChange?() }
    }

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another paired watch: activate again for the new one.
        session.activate()
    }

    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.onStateChange?() }
    }
    #endif

    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let payload = SendableDictionary(applicationContext)
        Task { @MainActor in self.deliver(payload.value, reply: nil) }
    }

    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let payload = SendableDictionary(userInfo)
        Task { @MainActor in self.deliver(payload.value, reply: nil) }
    }

    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let payload = SendableDictionary(message)
        Task { @MainActor in self.deliver(payload.value, reply: nil) }
    }

    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let payload = SendableDictionary(message)
        let handler = SendableReply(replyHandler)
        Task { @MainActor in
            self.deliver(payload.value) { response in handler.call(response) }
            // Always answer exactly once so the sender is not left waiting for a timeout.
            handler.call([:])
        }
    }

    nonisolated public func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        // Cancelled transfers are expected: batches are cumulative and replace each other.
        guard let error, !userInfoTransfer.isTransferring else { return }
        let message = error.localizedDescription
        Task { @MainActor in self.lastError = message }
    }
}

/// WatchConnectivity dictionaries only contain property-list values, which are safe to
/// hand across actors.
private struct SendableDictionary: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
}

/// Calls WatchConnectivity's reply handler at most once.
private final class SendableReply: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (([String: Any]) -> Void)?
    init(_ handler: @escaping ([String: Any]) -> Void) { self.handler = handler }
    func call(_ value: [String: Any]) {
        lock.lock()
        let current = handler
        handler = nil
        lock.unlock()
        current?(value)
    }
}
#endif
