import Foundation

/// Coalesces concurrent app-icon badge mirror requests during restoration.
actor AppIconBadgeRefreshFlight {
    static let shared = AppIconBadgeRefreshFlight()

    private var inFlight: Task<Void, Never>?
    private var pendingTrailingRefresh = false

    func run(_ operation: @escaping @Sendable () async -> Void) async {
        if inFlight != nil {
            pendingTrailingRefresh = true
            await inFlight?.value
            return
        }
        repeat {
            pendingTrailingRefresh = false
            let task = Task {
                await operation()
            }
            inFlight = task
            await task.value
            inFlight = nil
        } while pendingTrailingRefresh
    }

    func resetForTests() {
        inFlight?.cancel()
        inFlight = nil
        pendingTrailingRefresh = false
    }
}
