import Foundation

/// Single-flight entity summary hydration — stale completions cannot resurrect deleted entities.
actor SocialEntitySummaryHydrationFlight {
    static let shared = SocialEntitySummaryHydrationFlight()

    private var generationByKey: [String: UInt64] = [:]
    private var inFlight: [String: Task<FeedTimelineEntry?, Never>] = [:]

    func bumpGeneration(entityKey: String) -> UInt64 {
        let next = (generationByKey[entityKey] ?? 0) &+ 1
        generationByKey[entityKey] = next
        inFlight[entityKey]?.cancel()
        inFlight[entityKey] = nil
        return next
    }

    func currentGeneration(entityKey: String) -> UInt64 {
        generationByKey[entityKey] ?? 0
    }

    func hydrate(
        entityKey: String,
        generation: UInt64,
        work: @escaping @Sendable () async -> FeedTimelineEntry?
    ) async -> FeedTimelineEntry? {
        if let existing = inFlight[entityKey] {
            #if DEBUG
            SocialEntityRealtimeDebugLog.summaryHydrationCoalesced(
                table: entityKey.split(separator: ":").first.map(String.init) ?? "",
                id: entityKey
            )
            #endif
            return await existing.value
        }
        let task = Task {
            await work()
        }
        inFlight[entityKey] = task
        let result = await task.value
        inFlight.removeValue(forKey: entityKey)
        guard generationByKey[entityKey] == generation else { return nil }
        return result
    }

    func reset() {
        generationByKey.removeAll()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
    }
}
