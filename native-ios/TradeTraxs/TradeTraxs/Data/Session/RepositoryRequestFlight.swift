import Foundation
import Synchronization

private enum RepositoryRequestCoalesceOutcome<T: Sendable> {
    case join(Task<T, Error>)
    case lead(Task<T, Error>)
}

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
nonisolated final class RepositoryRequestFlight: @unchecked Sendable {
    static let shared = RepositoryRequestFlight()

    private struct FlightState {
        var tasks: [String: Any] = [:]
    }

    private let state = Mutex(FlightState())

    private init() {}

    /// Shares one network operation across concurrent callers with the same key.
    func coalesce<T: Sendable>(
        key: String,
        resource: String,
        fetch: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let outcome: RepositoryRequestCoalesceOutcome<T> = state.withLock { flight in
            if let existing = flight.tasks[key] as? Task<T, Error> {
                return .join(existing)
            }
            let task = Task<T, Error> {
                try await fetch()
            }
            flight.tasks[key] = task
            return .lead(task)
        }

        switch outcome {
        case .join(let existing):
            #if DEBUG
            SessionNetworkProbe.record(
                .requestCoalesced,
                resource: resource,
                detail: key
            )
            #endif
            return try await existing.value
        case .lead(let task):
            defer {
                state.withLock { flight in
                    flight.tasks[key] = nil
                }
            }
            return try await task.value
        }
    }

    /// Drops in-flight bookkeeping. Pass `prefix` to scope invalidation.
    ///
    /// Outstanding tasks may still complete; results are ignored by future callers.
    func invalidate(prefix: String? = nil) {
        state.withLock { flight in
            if let prefix {
                for key in flight.tasks.keys.filter({ $0.hasPrefix(prefix) }) {
                    flight.tasks[key] = nil
                }
            } else {
                flight.tasks = [:]
            }
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
