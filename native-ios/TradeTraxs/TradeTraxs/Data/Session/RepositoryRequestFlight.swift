import Foundation

/// Shared single-flight coalescer for identical concurrent repository network operations.
///
/// Callers with the same `key` share one in-flight `Task`. Completed flights are cleared
/// immediately — this is **not** a result cache. Session stores remain responsible for
/// TTL / disk / memory caching where product policy already requires it.
///
/// Standard repository lifecycle (composition):
/// - **fetch** — repository method (may check memory/session cache first)
/// - **coalesce** — wrap the network body with ``coalesce(key:resource:fetch:)``
/// - **refresh(force:)** — feature/bootstrap layer clears cache then fetches
/// - **invalidate** — drop in-flight bookkeeping on logout / identity change
final class RepositoryRequestFlight: @unchecked Sendable {
    static let shared = RepositoryRequestFlight()

    private let lock = NSLock()
    private var tasks: [String: Any] = [:]

    private init() {}

    /// Shares one network operation across concurrent callers with the same key.
    func coalesce<T: Sendable>(
        key: String,
        resource: String,
        fetch: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        lock.lock()
        if let existing = tasks[key] as? Task<T, Error> {
            lock.unlock()
            #if DEBUG
            SessionNetworkProbe.record(
                .requestCoalesced,
                resource: resource,
                detail: key
            )
            #endif
            return try await existing.value
        }

        let task = Task<T, Error> {
            try await fetch()
        }
        tasks[key] = task
        lock.unlock()

        defer {
            lock.lock()
            tasks[key] = nil
            lock.unlock()
        }
        return try await task.value
    }

    /// Drops in-flight bookkeeping. Pass `prefix` to scope invalidation.
    ///
    /// Outstanding tasks may still complete; results are ignored by future callers.
    func invalidate(prefix: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let prefix {
            for key in tasks.keys.filter({ $0.hasPrefix(prefix) }) {
                tasks[key] = nil
            }
        } else {
            tasks = [:]
        }
        #if DEBUG
        SessionNetworkProbe.record(
            .cacheInvalidated,
            resource: "repositoryRequestFlight",
            detail: prefix ?? "all"
        )
        #endif
    }
}
