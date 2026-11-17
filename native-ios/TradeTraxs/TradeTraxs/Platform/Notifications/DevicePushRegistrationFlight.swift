import Foundation

/// Coalesces concurrent `/api/push/register` uploads for the same token.
/// A finished upload does not suppress a later one: the server row can be missing
/// even when this process already tried, and the login shell must not block the
/// production client.
actor DevicePushRegistrationFlight {
    static let shared = DevicePushRegistrationFlight()

    private var inFlightKey: String?
    private var inFlightTask: Task<Void, Error>?

    func register(
        token: String,
        previousDeviceToken: String?,
        operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        let key = "\(token)|\(previousDeviceToken ?? "-")"
        if inFlightKey == key, let task = inFlightTask {
            try await task.value
            return
        }
        let task = Task {
            try await operation()
        }
        inFlightKey = key
        inFlightTask = task
        defer {
            if inFlightKey == key {
                inFlightKey = nil
                inFlightTask = nil
            }
        }
        try await task.value
    }

    func resetForLogout() {
        inFlightTask?.cancel()
        inFlightKey = nil
        inFlightTask = nil
    }
}
