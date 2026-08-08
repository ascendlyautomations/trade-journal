import Foundation
import Observation

/// Higher-level network posture used by repositories / UI feedback later.
@Observable
final class NetworkMonitor {
    private let reachability: ReachabilityMonitor
    private(set) var status: ReachabilityStatus

    init(reachability: ReachabilityMonitor) {
        self.reachability = reachability
        self.status = reachability.status
    }

    /// Call once after construction to subscribe to path updates on the main actor.
    func start() {
        reachability.setStatusHandler { [weak self] status in
            Task { @MainActor in
                self?.status = status
            }
        }
    }

    var isOnline: Bool { status == .satisfied }

    /// Maps current posture into Experience feedback (non-blocking).
    var feedbackHint: FeedbackState {
        isOnline ? .idle : .offline(message: "You're offline. Some actions may be unavailable.")
    }

    func requireOnline() throws {
        guard reachability.isOnline else { throw NetworkError.connectivity }
    }
}
