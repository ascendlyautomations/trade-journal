import Foundation

/// Coalesces concurrent `/api/push/register` uploads for the same token/installation.
actor DevicePushRegistrationFlight {
    static let shared = DevicePushRegistrationFlight()

    private var inFlightKey: String?
    private var inFlightTask: Task<Void, Error>?
    private var lastRegisteredToken: String?

    func register(
        token: String,
        previousDeviceToken: String?,
        operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        if lastRegisteredToken == token { return }
        let key = "\(token)|\(previousDeviceToken ?? "-")"
        if inFlightKey == key, let task = inFlightTask {
            _ = try? await task.value
            if lastRegisteredToken == token { return }
        }
        let task = Task {
            try await operation()
            lastRegisteredToken = token
        }
        inFlightKey = key
        inFlightTask = task
        defer {
            inFlightKey = nil
            inFlightTask = nil
        }
        try await task.value
    }

    func resetForLogout() {
        lastRegisteredToken = nil
        inFlightTask?.cancel()
        inFlightKey = nil
        inFlightTask = nil
    }
}
