import Foundation

@MainActor
enum TradingRulesComplianceRecomputeCoordinator {
    private static var generation: UInt64 = 0
    private static var inFlight: Task<Void, Never>?
    private static var inFlightGeneration: UInt64 = 0

    static var currentGeneration: UInt64 { generation }

    /// Drops in-flight work so a newer publish cannot lose to an older completion.
    /// Leaves the session store in place for ordinary preference and trade invalidation.
    static func reset() {
        invalidateInFlight()
    }

    /// Authenticated viewer change. Cancels in-flight work and drops the published snapshot.
    static func resetForSessionBoundary() {
        invalidateInFlight()
        TradingRulesComplianceSessionStore.shared.reset()
    }

    static func isCurrent(_ token: UInt64) -> Bool {
        token == generation
    }

    /// Skips only when the store is showing this profile, scope, and input fingerprint.
    static func shouldSkip(
        profileID: ProfileID,
        scopeFingerprint: String,
        inputFingerprint: String
    ) -> Bool {
        inFlight == nil
            && TradingRulesComplianceSessionStore.shared.matchesPublishedSnapshot(
                profileID: profileID,
                scopeFingerprint: scopeFingerprint,
                inputFingerprint: inputFingerprint
            )
    }

    @discardableResult
    static func beginPublish() -> UInt64 {
        invalidateInFlight()
        return generation
    }

    static func request(
        profileID: ProfileID,
        scopeFingerprint: String,
        fingerprint: String,
        work: @escaping @Sendable () async -> TradingRulesComplianceCompute.ScopedPayload,
        onComplete: @escaping (TradingRulesComplianceCompute.ScopedPayload) -> Void
    ) {
        if shouldSkip(
            profileID: profileID,
            scopeFingerprint: scopeFingerprint,
            inputFingerprint: fingerprint
        ) {
            return
        }

        let token = beginPublish()
        let task = Task { @MainActor in
            let payload = await work()
            let stale = Task.isCancelled || !isCurrent(token)
            finishInFlight(token: token)
            guard !stale else { return }
            onComplete(payload)
        }
        inFlight = task
        inFlightGeneration = token
    }

    private static func invalidateInFlight() {
        generation &+= 1
        inFlight?.cancel()
        inFlight = nil
        inFlightGeneration = 0
    }

    /// Cancellation and stale completions both release the in-flight slot.
    private static func finishInFlight(token: UInt64) {
        guard inFlightGeneration == token else { return }
        inFlight = nil
        inFlightGeneration = 0
    }
}
