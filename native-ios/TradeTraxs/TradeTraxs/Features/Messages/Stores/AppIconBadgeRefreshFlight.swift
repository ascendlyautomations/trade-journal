import Foundation

/// Coalesces concurrent app-icon badge mirror requests during restoration.
actor AppIconBadgeRefreshFlight {
    static let shared = AppIconBadgeRefreshFlight()

    private var slotID: UUID?
    private var inFlight: Task<Void, Never>?

    func run(_ operation: @escaping @Sendable () async -> Void) async {
        if let existing = inFlight {
            await existing.value
            return
        }
        let id = UUID()
        let task = Task {
            await operation()
        }
        slotID = id
        inFlight = task
        await task.value
        if slotID == id {
            inFlight = nil
            slotID = nil
        }
    }

    func resetForTests() {
        inFlight?.cancel()
        inFlight = nil
        slotID = nil
    }
}
