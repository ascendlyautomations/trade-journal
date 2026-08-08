import Foundation
import Network

/// Path status for offline-aware UI / request gating.
nonisolated enum ReachabilityStatus: String, Sendable, Equatable {
    case satisfied
    case unsatisfied
    case requiresConnection
}

/// Thread-safe path snapshot readable from any isolation domain.
nonisolated final class ReachabilityPathState: @unchecked Sendable {
    private let lock = NSLock()
    private var _status: ReachabilityStatus = .satisfied
    private var _handler: (@Sendable (ReachabilityStatus) -> Void)?

    var status: ReachabilityStatus {
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    var isOnline: Bool { status == .satisfied }

    func update(_ status: ReachabilityStatus) {
        let handler: (@Sendable (ReachabilityStatus) -> Void)?
        lock.lock()
        _status = status
        handler = _handler
        lock.unlock()
        handler?(status)
    }

    func setHandler(_ handler: (@Sendable (ReachabilityStatus) -> Void)?) {
        lock.lock()
        _handler = handler
        lock.unlock()
    }
}

nonisolated protocol ReachabilityMonitoring: AnyObject, Sendable {
    var pathState: ReachabilityPathState { get }
    var status: ReachabilityStatus { get }
    var isOnline: Bool { get }
}

/// NWPathMonitor-backed reachability. UI observes via ``NetworkMonitor``.
nonisolated final class ReachabilityMonitor: ReachabilityMonitoring, @unchecked Sendable {
    let pathState = ReachabilityPathState()
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    var status: ReachabilityStatus { pathState.status }
    var isOnline: Bool { pathState.isOnline }

    init(
        monitor: NWPathMonitor = NWPathMonitor(),
        queue: DispatchQueue = DispatchQueue(label: "com.tradetraxs.ios.reachability")
    ) {
        self.monitor = monitor
        self.queue = queue
        start()
    }

    deinit {
        monitor.cancel()
    }

    func setStatusHandler(_ handler: (@Sendable (ReachabilityStatus) -> Void)?) {
        pathState.setHandler(handler)
    }

    private func start() {
        monitor.pathUpdateHandler = { [pathState] path in
            let mapped: ReachabilityStatus
            switch path.status {
            case .satisfied:
                mapped = .satisfied
            case .unsatisfied:
                mapped = .unsatisfied
            case .requiresConnection:
                mapped = .requiresConnection
            @unknown default:
                mapped = .unsatisfied
            }
            pathState.update(mapped)
        }
        monitor.start(queue: queue)
    }
}
