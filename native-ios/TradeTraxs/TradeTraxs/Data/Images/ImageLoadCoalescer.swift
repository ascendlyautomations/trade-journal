import Foundation

/// One in-flight network fetch per pipeline cache key.
actor ImageLoadCoalescer {
    private var inflight: [String: Task<Data, Error>] = [:]

    func load(key: String, operation: @Sendable @escaping () async throws -> Data) async throws -> Data {
        if let existing = inflight[key] {
            #if DEBUG
            MediaEgressTracker.recordImageCoalescedDuplicate()
            #endif
            return try await existing.value
        }
        let task = Task { try await operation() }
        inflight[key] = task
        defer { inflight.removeValue(forKey: key) }
        return try await task.value
    }

    func cancelAll() {
        for task in inflight.values {
            task.cancel()
        }
        inflight.removeAll()
    }
}
