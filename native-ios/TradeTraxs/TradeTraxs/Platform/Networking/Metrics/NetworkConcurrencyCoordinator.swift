import Foundation
import OSLog

/// Visible vs background scheduling for Supabase HTTP work.
nonisolated enum NetworkSchedulingPriority: Sendable {
    /// GoTrue token refresh / session validation — never waits on background or media budgets.
    case criticalAuth
    case visible
    case background
}

/// Enforces background concurrency budget; visible work never waits on background slots.
actor NetworkConcurrencyCoordinator {
    static let shared = NetworkConcurrencyCoordinator()

    /// Conservative startup budget — background callers wait beyond this count.
    static let maxBackgroundConcurrent = 4
    /// Storage / render image fetches — separate from JSON RPC budget.
    static let maxBackgroundMediaConcurrent = 3
    /// Cap concurrent visible REST/RPC so avatar storms cannot starve bootstraps.
    static let maxVisibleConcurrent = 8

    private var criticalAuthInFlight = 0
    private var visibleInFlight = 0
    private var backgroundInFlight = 0
    private var backgroundMediaInFlight = 0
    private struct BackgroundWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Never>
    }

    private var backgroundWaiters: [BackgroundWaiter] = []
    /// Blocks authenticated REST/RPC acquires after logout — not GoTrue bootstrap/token exchange.
    private var authenticatedSessionNetworkingBlocked = false
    private var sessionEndGeneration: UInt64 = 0

    private init() {}

    /// Hard session boundary — resume every waiter and reject new authenticated acquires until login succeeds.
    func resetForAuthenticatedSessionEnd(authGeneration: UInt64) -> (waitersReleased: Int, inFlightCleared: Int) {
        authenticatedSessionNetworkingBlocked = true
        sessionEndGeneration = authGeneration
        let waitersReleased = backgroundWaiters.count
        drainBackgroundWaiters()
        let inFlightCleared =
            criticalAuthInFlight + visibleInFlight + backgroundInFlight + backgroundMediaInFlight
        criticalAuthInFlight = 0
        visibleInFlight = 0
        backgroundInFlight = 0
        backgroundMediaInFlight = 0
#if DEBUG
        AuthLifecycleTrace.log(
            operation: "network.authenticatedSessionBlocked",
            authGeneration: authGeneration,
            sessionGeneration: authGeneration,
            phase: "unauthenticated",
            decision: "allowed",
            reason: "logoutSessionEnd"
        )
#endif
        return (waitersReleased, inFlightCleared)
    }

    func markAuthenticatedSessionActive(authGeneration: UInt64) {
        authenticatedSessionNetworkingBlocked = false
        sessionEndGeneration = authGeneration
#if DEBUG
        AuthLifecycleTrace.log(
            operation: "network.authenticatedSessionActive",
            authGeneration: authGeneration,
            sessionGeneration: authGeneration,
            phase: "authenticated",
            decision: "allowed",
            reason: "sessionInstalled"
        )
#endif
    }

    func currentSessionEndGeneration() -> UInt64 {
        sessionEndGeneration
    }

    var totalInFlight: Int {
        criticalAuthInFlight + visibleInFlight + backgroundInFlight + backgroundMediaInFlight
    }
    var waitingBackgroundCount: Int { backgroundWaiters.count }

    /// Acquires a slot, runs `operation`, then releases — covers full network lifetime per attempt.
    func runWithSlot<T: Sendable>(
        priority: NetworkSchedulingPriority,
        path: String,
        host: String,
        method: HTTPMethod = .get,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire(priority: priority, path: path, host: host, method: method)
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
        (
            totalInFlight,
            criticalAuthInFlight + visibleInFlight,
            backgroundInFlight + backgroundMediaInFlight,
            backgroundWaiters.count
        )
    }

    private func isStorageMediaPath(_ path: String) -> Bool {
        path.hasPrefix("/storage/v1/object/") || path.contains("/storage/v1/render/")
    }

    private func acquire(
        priority: NetworkSchedulingPriority,
        path: String,
        host: String,
        method: HTTPMethod
    ) async throws {
        if Task.isCancelled {
            throw CancellationError()
        }
        if authenticatedSessionNetworkingBlocked,
           !AuthNetworkPolicy.allowsDuringAuthenticatedSessionEnd(path: path, method: method)
        {
#if DEBUG
            AuthLifecycleTrace.log(
                operation: "network.acquire",
                authGeneration: AuthLifecycleGeneration.current(),
                sessionGeneration: sessionEndGeneration,
                requestPath: path,
                decision: "cancelled",
                reason: "authenticatedSessionEnd",
                cancelInitiatorGeneration: sessionEndGeneration
            )
#endif
            throw CancellationError()
        }
        switch priority {
        case .criticalAuth:
            criticalAuthInFlight += 1
            #if DEBUG
            NetworkConcurrencyProbe.logAcquire(
                path: path,
                host: host,
                priority: priority,
                visibleInFlight: criticalAuthInFlight + visibleInFlight,
                backgroundInFlight: backgroundInFlight + backgroundMediaInFlight,
                waitingBackground: backgroundWaiters.count
            )
            #endif

        case .visible:
            while visibleInFlight >= Self.maxVisibleConcurrent {
                try await Task.sleep(nanoseconds: 25_000_000)
                if Task.isCancelled { throw CancellationError() }
            }
            visibleInFlight += 1
            #if DEBUG
            NetworkConcurrencyProbe.logAcquire(
                path: path,
                host: host,
                priority: priority,
                visibleInFlight: criticalAuthInFlight + visibleInFlight,
                backgroundInFlight: backgroundInFlight + backgroundMediaInFlight,
                waitingBackground: backgroundWaiters.count
            )
            #endif

        case .background:
            if isStorageMediaPath(path) {
                while backgroundMediaInFlight >= Self.maxBackgroundMediaConcurrent {
                    try await Task.sleep(nanoseconds: 25_000_000)
                    if Task.isCancelled { throw CancellationError() }
                }
                backgroundMediaInFlight += 1
                #if DEBUG
                NetworkConcurrencyProbe.logAcquire(
                    path: path,
                    host: host,
                    priority: priority,
                    visibleInFlight: criticalAuthInFlight + visibleInFlight,
                    backgroundInFlight: backgroundInFlight + backgroundMediaInFlight,
                    waitingBackground: backgroundWaiters.count
                )
                #endif
                return
            }
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
                    Task { await self.cancelBackgroundWaiter(id: waiterID) }
                }
                if Task.isCancelled { throw CancellationError() }
                if authenticatedSessionNetworkingBlocked,
                   !AuthNetworkPolicy.allowsDuringAuthenticatedSessionEnd(path: path, method: method)
                {
                    throw CancellationError()
                }
            }
            if Task.isCancelled { throw CancellationError() }
            if authenticatedSessionNetworkingBlocked,
               !AuthNetworkPolicy.allowsDuringAuthenticatedSessionEnd(path: path, method: method)
            {
                throw CancellationError()
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
        case .criticalAuth:
            criticalAuthInFlight = max(0, criticalAuthInFlight - 1)
        case .visible:
            visibleInFlight = max(0, visibleInFlight - 1)
        case .background:
            if isStorageMediaPath(path) {
                backgroundMediaInFlight = max(0, backgroundMediaInFlight - 1)
            } else {
                backgroundInFlight = max(0, backgroundInFlight - 1)
                if !backgroundWaiters.isEmpty {
                    backgroundWaiters.removeFirst().continuation.resume()
                }
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

    /// Cancelled or session-invalidated waiters must resume exactly once.
    private func cancelBackgroundWaiter(id: UUID) {
        guard let index = backgroundWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = backgroundWaiters.remove(at: index)
        waiter.continuation.resume()
    }

    private func drainBackgroundWaiters() {
        let pending = backgroundWaiters
        backgroundWaiters.removeAll()
        for waiter in pending {
            waiter.continuation.resume()
        }
    }

    /// Classifies scheduling lane from path, method, and PostgREST query shape.
    nonisolated static func inferPriority(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = []
    ) -> NetworkSchedulingPriority {
        if path.contains("/rest/v1/rpc/") {
            let rpc = path.split(separator: "/").last.map(String.init) ?? path
            if ActiveScreenBootstrapPriorityGate.prefersVisibleBootstrap(rpcName: rpc) {
                return .visible
            }
            if rpc == BackendV2Versioning.RPCName.activity.rawValue,
               ActivityFeedBootstrapPriorityGate.prefersVisibleBootstrap
            {
                return .visible
            }
            return visibleBlockingRPCs.contains(rpc) ? .visible : .background
        }

        if path.hasPrefix("/storage/v1/object/") || path.contains("/storage/v1/render/") {
            return .background
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

        if path.hasPrefix("/auth/v1/token"), method == .post {
            return .criticalAuth
        }
        if path.hasPrefix("/auth/v1/"), method == .post {
            return .criticalAuth
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
        BackendV2Versioning.RPCName.session.rawValue,
        BackendV2Versioning.RPCName.dashboard.rawValue,
        BackendV2Versioning.RPCName.viewerSyncState.rawValue,
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
        BackendV2Versioning.RPCName.profileAnalyticsBootstrapV2.rawValue,
        BackendV2Versioning.RPCName.profilePublicAnalyticsRevision.rawValue,
        BackendV2Versioning.RPCName.room.rawValue,
        BackendV2Versioning.RPCName.calendar.rawValue,
        BackendV2Versioning.RPCName.analyticsDashboardBootstrapV3.rawValue,
        BackendV2Versioning.RPCName.analyticsDashboardAccountChartsV3.rawValue,
        BackendV2Versioning.RPCName.analyticsDashboardAggregateChartsV3.rawValue,
        BackendV2Versioning.RPCName.messaging.rawValue,
        BackendV2Versioning.RPCName.tradeRoomsHomeBootstrap.rawValue,
        BackendV2Versioning.RPCName.analyticsDailyRangeBootstrap.rawValue,
        BackendV2Versioning.RPCName.tradesListV2.rawValue,
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

nonisolated private func networkSchedulingPriorityLabel(_ priority: NetworkSchedulingPriority) -> String {
    switch priority {
    case .criticalAuth: return "criticalAuth"
    case .visible: return "visible"
    case .background: return "background"
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
            scheduling=\(networkSchedulingPriorityLabel(priority), privacy: .public)
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
            scheduling=\(networkSchedulingPriorityLabel(priority), privacy: .public)
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
