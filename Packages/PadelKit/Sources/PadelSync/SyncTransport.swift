import Foundation

/// The three delivery mechanisms WatchConnectivity offers, abstracted so the sync logic
/// can be tested without devices:
/// - latest state (application context): only the newest value matters, delivered when
///   the counterpart next runs. Used for iPhone → watch snapshots.
/// - durable queue (user-info transfers): every item is delivered, in order, even after
///   the sender quits. Used for watch → iPhone events while unreachable.
/// - immediate (messages): only when the counterpart is reachable; supports a reply.
///   Used for fast round trips. Delivery of a message is *not* proof of persistence;
///   only a later snapshot acknowledging the event is.
@MainActor
public protocol SyncTransport: AnyObject {
    var isReachable: Bool { get }
    /// Called on the main actor for every received message. `reply` is non-nil when the
    /// sender is waiting for an answer.
    var onReceive: ((SyncMessage, ((SyncMessage) -> Void)?) -> Void)? { get set }
    /// Called when reachability or activation changes.
    var onStateChange: (() -> Void)? { get set }

    func activate()
    func updateLatestState(_ message: SyncMessage) throws
    /// Queues a durable transfer. When `replacingPending` is true, older queued transfers
    /// of this kind are cancelled first (safe because batches are cumulative).
    func enqueueDurable(_ message: SyncMessage, replacingPending: Bool)
    func sendImmediate(_ message: SyncMessage, reply: ((SyncMessage) -> Void)?, failure: ((Error) -> Void)?)
}

/// An in-process transport pair for tests and previews. Supports unreachable periods,
/// dropped immediate messages, duplicated and reordered durable deliveries.
@MainActor
public final class InMemorySyncTransport: SyncTransport {
    public weak var peer: InMemorySyncTransport?
    public var isReachable: Bool = true { didSet { onStateChange?() } }
    public var onReceive: ((SyncMessage, ((SyncMessage) -> Void)?) -> Void)?
    public var onStateChange: (() -> Void)?

    /// Durable items waiting to be delivered to the peer.
    public private(set) var durableQueue: [SyncMessage] = []
    /// Latest state waiting to be delivered to the peer.
    public private(set) var pendingLatestState: SyncMessage?
    public var dropImmediateMessages = false
    public private(set) var sentImmediateCount = 0

    public struct Unreachable: Error {}

    public init() {}

    public static func pair() -> (InMemorySyncTransport, InMemorySyncTransport) {
        let a = InMemorySyncTransport(), b = InMemorySyncTransport()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    public func activate() {}

    public func updateLatestState(_ message: SyncMessage) throws {
        pendingLatestState = message
    }

    public func enqueueDurable(_ message: SyncMessage, replacingPending: Bool) {
        if replacingPending { durableQueue.removeAll { if case .eventBatch = $0 { true } else { false } } }
        durableQueue.append(message)
    }

    public func sendImmediate(_ message: SyncMessage, reply: ((SyncMessage) -> Void)?, failure: ((Error) -> Void)?) {
        sentImmediateCount += 1
        guard isReachable, let peer, !dropImmediateMessages else {
            failure?(Unreachable())
            return
        }
        peer.onReceive?(message, reply.map { handler in { response in handler(response) } })
    }

    // MARK: Test controls

    /// Delivers queued durable items and the latest state to the peer.
    public func deliverAll(duplicate: Bool = false, reversed: Bool = false) {
        guard let peer else { return }
        var items = durableQueue
        durableQueue = []
        if reversed { items.reverse() }
        if duplicate { items += items }
        for item in items { peer.onReceive?(item, nil) }
        if let state = pendingLatestState {
            pendingLatestState = nil
            peer.onReceive?(state, nil)
        }
    }

    /// Delivers only the latest state.
    public func deliverLatestState() {
        guard let peer, let state = pendingLatestState else { return }
        pendingLatestState = nil
        peer.onReceive?(state, nil)
    }

    /// Simulates losing everything queued (e.g. the transfer was cancelled by the system).
    public func dropQueued() {
        durableQueue = []
        pendingLatestState = nil
    }
}
