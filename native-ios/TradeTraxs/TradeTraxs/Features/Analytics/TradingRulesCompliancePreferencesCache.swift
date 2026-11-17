import Foundation

/// Session cache + single-flight for trading preferences used by compliance analytics.
@MainActor
enum TradingRulesCompliancePreferencesCache {
    private static var byProfile: [ProfileID: PreferenceRuleContext] = [:]
    private static var fingerprintByProfile: [ProfileID: String] = [:]
    private static var inFlight: [ProfileID: Task<TradingRulesComplianceSnapshotBuilder.PreferenceLoadOutcome, Never>] = [:]

    static func cachedContext(for profileID: ProfileID) -> PreferenceRuleContext? {
        byProfile[profileID]
    }

    static func store(_ context: PreferenceRuleContext, for profileID: ProfileID) {
        byProfile[profileID] = context
        fingerprintByProfile[profileID] = PreferenceComplianceEngine.fingerprint(context)
    }

    static func invalidate(profileID: ProfileID) {
        byProfile[profileID] = nil
        fingerprintByProfile[profileID] = nil
        inFlight[profileID]?.cancel()
        inFlight[profileID] = nil
    }

    static func resetAll() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        byProfile.removeAll()
        fingerprintByProfile.removeAll()
    }

    static func load(
        for profileID: ProfileID,
        repository: (any TradingPreferencesRepository)?,
        injected: PreferenceRuleContext?
    ) async -> TradingRulesComplianceSnapshotBuilder.PreferenceLoadOutcome {
        if let injected {
            store(injected, for: profileID)
            return .loaded(injected)
        }
        if let cached = byProfile[profileID] {
            return .loaded(cached)
        }
        if let inFlightTask = inFlight[profileID] {
            return await inFlightTask.value
        }

        guard let repository else { return .skipped }

        let task = Task {
            await fetchFromNetwork(profileID: profileID, repository: repository)
        }
        inFlight[profileID] = task
        defer { inFlight[profileID] = nil }
        let outcome = await task.value
        if case .loaded(let context) = outcome {
            store(context, for: profileID)
        }
        return outcome
    }

    private static func fetchFromNetwork(
        profileID: ProfileID,
        repository: any TradingPreferencesRepository
    ) async -> TradingRulesComplianceSnapshotBuilder.PreferenceLoadOutcome {
        do {
            async let global = repository.globalPreferences(for: profileID)
            async let overrides = repository.accountOverrides(for: profileID)
            async let revisions = repository.revisions(for: profileID)
            return .loaded(
                PreferenceRuleContext(
                    revisions: try await revisions,
                    global: try await global,
                    overrides: try await overrides
                )
            )
        } catch {
            return .failed("Couldn't load your trading rules. Check your connection and try again.")
        }
    }
}
