import Foundation
import OSLog

/// Visible vs background scheduling for Supabase HTTP work.
nonisolated enum NetworkSchedulingPriority: Sendable {
    case visible
    case background
}

/// Enforces background concurrency budget; visible work never waits on background slots.
actor NetworkConcurrencyCoordinator {
    static let shared = NetworkConcurrencyCoordinator()

    /// Conservative startup budget — background callers wait beyond this count.
    static let maxBackgroundConcurrent = 4

    private var visibleInFlight = 0
    private var backgroundInFlight = 0
    private struct BackgroundWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Never>
    }

    private var backgroundWaiters: [BackgroundWaiter] = []

    private init() {}

    var totalInFlight: Int { visibleInFlight + backgroundInFlight }
    var waitingBackgroundCount: Int { backgroundWaiters.count }

    /// Acquires a slot, runs `operation`, then releases — covers full network lifetime per attempt.
    func runWithSlot<T: Sendable>(
        priority: NetworkSchedulingPriority,
        path: String,
        host: String,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire(priority: priority, path: path, host: host)
        do {
            let value = try await operation()
            release(priority: priority, path: path, host: host)
            return value
        } catch {
            release(priority: priority, path: path, host: host)
            throw error
        }
    }

    func snapshot() -> (total: Int, visible: Int, background: Int, waiting: Int) {
        (totalInFlight, visibleInFlight, backgroundInFlight, backgroundWaiters.count)
    }

    private func acquire(priority: NetworkSchedulingPriority, path: String, host: String) async throws {
        switch priority {
        case .visible:
            visibleInFlight += 1
            #if DEBUG
            NetworkConcurrencyProbe.logAcquire(
                path: path,
                host: host,
                priority: priority,
                visibleInFlight: visibleInFlight,
                backgroundInFlight: backgroundInFlight,
                waitingBackground: backgroundWaiters.count
            )
            #endif

        case .background:
            while backgroundInFlight >= Self.maxBackgroundConcurrent {
                #if DEBUG
                NetworkConcurrencyProbe.logWait(
                    path: path,
                    host: host,
                    priority: priority,
                    visibleInFlight: visibleInFlight,
                    backgroundInFlight: backgroundInFlight,
                    waitingBackground: backgroundWaiters.count + 1
                )
                #endif
                let waiterID = UUID()
                await withTaskCancellationHandler {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        backgroundWaiters.append(
                            BackgroundWaiter(id: waiterID, continuation: continuation)
                        )
                    }
                } onCancel: {
                    Task { await self.removeBackgroundWaiter(id: waiterID) }
                }
                if Task.isCancelled { throw CancellationError() }
            }
            backgroundInFlight += 1
            #if DEBUG
            NetworkConcurrencyProbe.logAcquire(
                path: path,
                host: host,
                priority: priority,
                visibleInFlight: visibleInFlight,
                backgroundInFlight: backgroundInFlight,
                waitingBackground: backgroundWaiters.count
            )
            #endif
        }
    }

    private func release(priority: NetworkSchedulingPriority, path: String, host: String) {
        switch priority {
        case .visible:
            visibleInFlight = max(0, visibleInFlight - 1)
        case .background:
            backgroundInFlight = max(0, backgroundInFlight - 1)
            if !backgroundWaiters.isEmpty {
                backgroundWaiters.removeFirst().continuation.resume()
            }
        }
        #if DEBUG
        NetworkConcurrencyProbe.logRelease(
            path: path,
            host: host,
            priority: priority,
            visibleInFlight: visibleInFlight,
            backgroundInFlight: backgroundInFlight,
            waitingBackground: backgroundWaiters.count
        )
        #endif
    }

    /// Cancelled waiters leave the queue without acquiring a slot.
    private func removeBackgroundWaiter(id: UUID) {
        guard let index = backgroundWaiters.firstIndex(where: { $0.id == id }) else { return }
        backgroundWaiters.remove(at: index)
    }

    /// Classifies scheduling lane from path, method, and PostgREST query shape.
    nonisolated static func inferPriority(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = []
    ) -> NetworkSchedulingPriority {
        if path.contains("/rest/v1/rpc/") {
            let rpc = path.split(separator: "/").last.map(String.init) ?? path
            if rpc == BackendV2Versioning.RPCName.activity.rawValue,
               ActivityFeedBootstrapPriorityGate.prefersVisibleBootstrap
            {
                return .visible
            }
            return visibleBlockingRPCs.contains(rpc) ? .visible : .background
        }

        if path.hasPrefix("/storage/v1/object/") || path.contains("/storage/v1/render/") {
            return method == .get ? .visible : .background
        }

        if path.hasPrefix("/rest/v1/") {
            if method == .post || method == .patch || method == .put {
                if path.hasPrefix("/rest/v1/messages")
                    || path.hasPrefix("/rest/v1/room_messages")
                    || path.contains("/rest/v1/rpc/")
                {
                    return .visible
                }
            }
            if method == .get,
               WithdrawalsHydrationPriorityGate.prefersVisibleHydration,
               isWithdrawalsLedgerOrCycleTable(path: path)
            {
                return .visible
            }
            if method == .get, isPrimaryKeyEntityLookup(path: path, queryItems: queryItems) {
                return .visible
            }
            return .background
        }

        if path.contains("/functions/v1/") || path.hasPrefix("/api/push/") {
            return .background
        }

        if path.hasPrefix("/auth/v1/"), method == .post {
            return .visible
        }

        if method == .get,
           BrokerIntegrationsLoadPriorityGate.prefersVisibleBrokerConnectionLoad,
           Self.isBrokerIntegrationsVisibleBFFPath(path)
        {
            return .visible
        }

        return .background
    }

    /// Connection list + account discovery while Broker Integrations is on screen — not background prefetch.
    private static func isBrokerIntegrationsVisibleBFFPath(_ path: String) -> Bool {
        if path == "/api/integrations/tradovate/connections" { return true }
        if path == "/api/integrations/rithmic/connections" { return true }
        if path.hasPrefix("/api/integrations/tradovate/connections/"), path.hasSuffix("/accounts") {
            return true
        }
        if path.hasPrefix("/api/integrations/rithmic/connections/"), path.hasSuffix("/accounts") {
            return true
        }
        return false
    }

    /// User-facing screen bootstraps and blocking detail loads — not capped by background budget.
    private static let visibleBlockingRPCs: Set<String> = [
        BackendV2Versioning.RPCName.conversationThread.rawValue,
        BackendV2Versioning.RPCName.feed.rawValue,
        BackendV2Versioning.RPCName.tradesList.rawValue,
        BackendV2Versioning.RPCName.tradeDetail.rawValue,
        BackendV2Versioning.RPCName.postDetail.rawValue,
        BackendV2Versioning.RPCName.profile.rawValue,
        BackendV2Versioning.RPCName.profileTabTrades.rawValue,
        BackendV2Versioning.RPCName.profileTabPosts.rawValue,
        BackendV2Versioning.RPCName.profileTabReels.rawValue,
        BackendV2Versioning.RPCName.profileTabAchievements.rawValue,
        BackendV2Versioning.RPCName.profileStatisticsBootstrap.rawValue,
        BackendV2Versioning.RPCName.room.rawValue,
        BackendV2Versioning.RPCName.calendar.rawValue,
    ]

    /// GET by primary key / id batch — trade detail, feed hydration, achievement fetch, etc.
    private static let visibleEntityTables: Set<String> = [
        "trades",
        "achievements",
        "posts",
        "profile_posts",
        "reels",
        "profiles",
    ]

    private static func isWithdrawalsLedgerOrCycleTable(path: String) -> Bool {
        guard path.hasPrefix("/rest/v1/") else { return false }
        let table = String(path.dropFirst("/rest/v1/".count))
        return table == "account_payout_entries" || table == "account_payout_cycles"
    }

    private static func isPrimaryKeyEntityLookup(path: String, queryItems: [URLQueryItem]) -> Bool {
        guard path.hasPrefix("/rest/v1/") else { return false }
        let table = String(path.dropFirst("/rest/v1/".count))
        guard visibleEntityTables.contains(table) else { return false }
        return queryItems.contains { item in
            guard item.name == "id", let value = item.value else { return false }
            return value.hasPrefix("eq.") || value.hasPrefix("in.")
        }
    }
}

#if DEBUG
nonisolated enum NetworkConcurrencyProbe {
    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "NetworkConcurrency"
    )

    static func logAcquire(
        path: String,
        host: String,
        priority: NetworkSchedulingPriority,
        visibleInFlight: Int,
        backgroundInFlight: Int,
        waitingBackground: Int
    ) {
        logEvent(
            verb: "ACQUIRE",
            path: path,
            host: host,
            priority: priority,
            visibleInFlight: visibleInFlight,
            backgroundInFlight: backgroundInFlight,
            waitingBackground: waitingBackground
        )
    }

    static func logWait(
        path: String,
        host: String,
        priority: NetworkSchedulingPriority,
        visibleInFlight: Int,
        backgroundInFlight: Int,
        waitingBackground: Int
    ) {
        logEvent(
            verb: "WAIT",
            path: path,
            host: host,
            priority: priority,
            visibleInFlight: visibleInFlight,
            backgroundInFlight: backgroundInFlight,
            waitingBackground: waitingBackground
        )
    }

    static func logRelease(
        path: String,
        host: String,
        priority: NetworkSchedulingPriority,
        visibleInFlight: Int,
        backgroundInFlight: Int,
        waitingBackground: Int
    ) {
        logEvent(
            verb: "RELEASE",
            path: path,
            host: host,
            priority: priority,
            visibleInFlight: visibleInFlight,
            backgroundInFlight: backgroundInFlight,
            waitingBackground: waitingBackground
        )
    }

    static func logSlowRequest(
        host: String,
        path: String,
        priority: NetworkSchedulingPriority,
        inFlightAtStart: Int,
        totalMs: Double,
        responseWaitMs: Double?
    ) {
        let request = path.split(separator: "/").last.map(String.init) ?? path
        let wait = responseWaitMs.map { String(format: "%.1f", $0) } ?? "n/a"
        logger.debug(
            """
            [NetworkConcurrency] slowRequest totalMs=\(String(format: "%.1f", totalMs), privacy: .public) \
            responseWaitMs=\(wait, privacy: .public) \
            inFlightAtStart=\(inFlightAtStart, privacy: .public) \
            host=\(host, privacy: .public) \
            request=\(request, privacy: .public) \
            scheduling=\(priority == .visible ? "visible" : "background", privacy: .public)
            """
        )
    }

    private static func logEvent(
        verb: String,
        path: String,
        host: String,
        priority: NetworkSchedulingPriority,
        visibleInFlight: Int,
        backgroundInFlight: Int,
        waitingBackground: Int
    ) {
        let request = path.split(separator: "/").last.map(String.init) ?? path
        let total = visibleInFlight + backgroundInFlight
        logger.debug(
            """
            [NetworkConcurrency] \(verb, privacy: .public) \
            inFlightTotal=\(total, privacy: .public) \
            visiblePriority=\(visibleInFlight, privacy: .public) \
            backgroundPriority=\(backgroundInFlight, privacy: .public) \
            waitingBackground=\(waitingBackground, privacy: .public) \
            host=\(host, privacy: .public) \
            request=\(request, privacy: .public) \
            scheduling=\(priority == .visible ? "visible" : "background", privacy: .public)
            """
        )
    }
}
#else
nonisolated enum NetworkConcurrencyProbe {
    static func logAcquire(
        path: String,
        host: String,
        priority: NetworkSchedulingPriority,
        visibleInFlight: Int,
        backgroundInFlight: Int,
        waitingBackground: Int
    ) {}

    static func logWait(
        path: String,
        host: String,
        priority: NetworkSchedulingPriority,
        visibleInFlight: Int,
        backgroundInFlight: Int,
        waitingBackground: Int
    ) {}

    static func logRelease(
        path: String,
        host: String,
        priority: NetworkSchedulingPriority,
        visibleInFlight: Int,
        backgroundInFlight: Int,
        waitingBackground: Int
    ) {}

    static func logSlowRequest(
        host: String,
        path: String,
        priority: NetworkSchedulingPriority,
        inFlightAtStart: Int,
        totalMs: Double,
        responseWaitMs: Double?
    ) {}
}
#endif
