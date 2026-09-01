import Foundation

/// Process-wide single-flight for token refresh / session restoration.
actor AuthRefreshSingleFlight {
    static let shared = AuthRefreshSingleFlight()

    private struct Slot {
        var id: UUID
        var generation: UInt64
        var fingerprint: String
        var task: Task<AuthenticationSession, Error>
    }

    private var slot: Slot?

    func bumpSessionGeneration() {
        slot?.task.cancel()
        slot = nil
    }

    func currentGeneration() -> UInt64 {
        0
    }

    /// One underlying refresh per fingerprint + generation; concurrent callers share the task.
    func refresh(
        fingerprint: String,
        generation: UInt64,
        operation: @escaping @Sendable () async throws -> AuthenticationSession
    ) async throws -> AuthenticationSession {
        if let slot,
           slot.generation == generation,
           slot.fingerprint == fingerprint
        {
            return try await slot.task.value
        }

        let slotID = UUID()
        let task = Task<AuthenticationSession, Error> {
            try await operation()
        }
        slot = Slot(id: slotID, generation: generation, fingerprint: fingerprint, task: task)

        do {
            let value = try await task.value
            if slot?.id == slotID {
                slot = nil
            }
            return value
        } catch {
            if slot?.id == slotID {
                slot = nil
            }
            throw error
        }
    }

    func cancelAll() {
        slot?.task.cancel()
        slot = nil
    }
}

nonisolated enum SessionFingerprint {
    static func make(_ session: AuthenticationSession) -> String {
        let material = session.refreshToken ?? session.userID.rawValue
        var hasher = Hasher()
        hasher.combine(material)
        return "fp-\(hasher.finalize())"
    }
}

nonisolated enum AuthBootstrapError: Error, Sendable, Equatable {
    case invalidSession
    case refreshInProgress
    case transientNetwork
    case serverFailure
    case cancelled
    case featureBootstrapFailure
    case deferredFeatureFailure
    case staleSessionResult
}
