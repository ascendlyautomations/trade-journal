import Foundation

/// Fires revision repair when reachability transitions to online (no polling).
nonisolated final class AnalyticsRevisionRepairNetworkObserver: @unchecked Sendable {
    static let shared = AnalyticsRevisionRepairNetworkObserver()

    private let lock = NSLock()
    private var lastStatus: ReachabilityStatus = .satisfied
    private var reachability: ReachabilityMonitor?

    private init() {}

    func configure(reachability: ReachabilityMonitor) {
        lock.lock()
        self.reachability = reachability
        lastStatus = reachability.status
        lock.unlock()

        reachability.setStatusHandler { [weak self] status in
            self?.handleStatusChange(status)
        }
    }

    private func handleStatusChange(_ status: ReachabilityStatus) {
        lock.lock()
        let previous = lastStatus
        lastStatus = status
        lock.unlock()

        guard previous != .satisfied, status == .satisfied else { return }
        Task {
            await AnalyticsRevisionRepairCoordinator.shared.requestRepair(.networkRegain)
            await SocialRealtimeReconciliationCoordinator.shared.requestRepair(.networkRegain)
        }
    }
}
