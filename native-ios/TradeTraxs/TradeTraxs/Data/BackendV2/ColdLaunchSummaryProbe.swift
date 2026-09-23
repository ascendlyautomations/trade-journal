import Foundation
import OSLog

#if DEBUG
/// One summarized DEBUG report for cold launch cache/network behavior.
nonisolated enum ColdLaunchSummaryProbe {
    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "ColdLaunch"
    )

    private static let lock = NSLock()
    nonisolated(unsafe) private static var launchStartedAt: CFAbsoluteTime?
    nonisolated(unsafe) private static var authenticatedShellAt: CFAbsoluteTime?
    nonisolated(unsafe) private static var dashboardFirstRenderAt: CFAbsoluteTime?
    nonisolated(unsafe) private static var serverVerifiedAt: CFAbsoluteTime?
    nonisolated(unsafe) private static var dashboardSource = "unknown"
    nonisolated(unsafe) private static var launchSource = "unknown"
    nonisolated(unsafe) private static var freshnessResult = "pending"
    nonisolated(unsafe) private static var persistentReads = 0
    nonisolated(unsafe) private static var networkRequestsBeforeDashboardRender = 0
    nonisolated(unsafe) private static var emitted = false

    static func markLaunchStarted() {
        lock.lock()
        defer { lock.unlock() }
        launchStartedAt = CFAbsoluteTimeGetCurrent()
        emitted = false
    }

    static func markLaunchSource(_ source: String) {
        lock.lock()
        defer { lock.unlock() }
        launchSource = source
    }

    static func markAuthenticatedShell() {
        lock.lock()
        defer { lock.unlock() }
        authenticatedShellAt = CFAbsoluteTimeGetCurrent()
    }

    static func markDashboardFirstRender(source: String) {
        lock.lock()
        defer { lock.unlock() }
        if dashboardFirstRenderAt == nil {
            dashboardFirstRenderAt = CFAbsoluteTimeGetCurrent()
            dashboardSource = source
            networkRequestsBeforeDashboardRender = SupabaseSessionUsage.snapshot().totalDatabaseRequests
        }
    }

    static func markPersistentRead() {
        lock.lock()
        defer { lock.unlock() }
        persistentReads += 1
    }

    static func markFreshnessResult(_ result: String) {
        lock.lock()
        defer { lock.unlock() }
        freshnessResult = result
        serverVerifiedAt = CFAbsoluteTimeGetCurrent()
        emitSummaryIfReadyLocked()
    }

    static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        launchStartedAt = nil
        authenticatedShellAt = nil
        dashboardFirstRenderAt = nil
        serverVerifiedAt = nil
        dashboardSource = "unknown"
        launchSource = "unknown"
        freshnessResult = "pending"
        persistentReads = 0
        networkRequestsBeforeDashboardRender = 0
        emitted = false
    }

    private static func emitSummaryIfReadyLocked() {
        guard !emitted else { return }
        guard dashboardFirstRenderAt != nil else { return }
        guard freshnessResult != "pending" else { return }
        emitted = true

        let usage = SupabaseSessionUsage.snapshot()
        let syncRPCs = usage.rpcByName[BackendV2Versioning.RPCName.viewerSyncState.rawValue, default: 0]
        let sessionRPCs = usage.rpcByName[BackendV2Versioning.RPCName.session.rawValue, default: 0]
        let dashboardRPCs = usage.rpcByName[BackendV2Versioning.RPCName.dashboard.rawValue, default: 0]
        let otherRequests = max(
            0,
            usage.totalDatabaseRequests - syncRPCs - sessionRPCs - dashboardRPCs
        )
        let diskIO = DiskCacheIOProbe.snapshot()
        let dashboardProbe = DashboardLoadProbe.snapshot()
        let persistentHits = SessionNetworkProbe.snapshotEvents()
            .filter { $0.0 == SessionNetworkProbe.Event.cacheHit.rawValue }.count
        let persistentMisses = SessionNetworkProbe.snapshotEvents()
            .filter { $0.0 == SessionNetworkProbe.Event.cacheMiss.rawValue }.count
        let dashboardRenderMs = msSinceLaunch(dashboardFirstRenderAt)
        let shellMs = msSinceLaunch(authenticatedShellAt)
        let verifiedMs = msSinceLaunch(serverVerifiedAt)

        let coldSummary = """
        [COLD LAUNCH SUMMARY]
        authenticatedShellMs=\(shellMs)
        dashboardFirstRenderMs=\(dashboardRenderMs)
        dashboardSource=\(dashboardSource)
        persistentReads=\(persistentReads)
        cacheHits=\(usage.cacheHits)
        networkFetches=\(SessionNetworkProbe.totalNetworkFetches())
        persistentCacheMisses=\(persistentMisses)
        syncStateRPCs=\(syncRPCs)
        sessionBootstrapRPCs=\(sessionRPCs)
        dashboardBootstrapRPCs=\(dashboardRPCs)
        otherRequests=\(otherRequests)
        structuredBytes=\(usage.bytesTransferred)
        freshness=\(freshnessResult)
        serverVerifiedMs=\(verifiedMs)
        """

        Task { @MainActor in
            let feedSource = FeedPersistentCacheProbe.source
            let profileSource = ProfilePersistentCacheProbe.source
            let tradeHistorySource = TradeHistoryCacheProbe.hit
                ? "disk" : (TradeHistoryCacheProbe.networkRequired ? "network" : "none")
            let calendarSource = CalendarCacheProbe.hit
                ? "disk" : (CalendarCacheProbe.networkRequired ? "network" : "none")
            let messagesSource = SocialCacheProbe.inboxSource == "disk"
                ? "disk" : (SocialCacheProbe.messagesFullBootstrapRPCs > 0 ? "network" : "none")
            let activitySource = SocialCacheProbe.activitySource == "disk"
                ? "disk" : (SocialCacheProbe.activityFullBootstrapRPCs > 0 ? "network" : "none")
            let roomsSource = SocialCacheProbe.roomSource == "disk" ? "disk" : "none"

            let performanceSummary = """
            [CACHE PERFORMANCE SUMMARY]
            launchSource=\(launchSource)
            dashboardFirstRenderMs=\(dashboardRenderMs)
            networkRequestsBeforeDashboardRender=\(networkRequestsBeforeDashboardRender)
            persistentCacheHits=\(persistentHits)
            persistentCacheMisses=\(persistentMisses)
            reconciliations=\(diskIO.reconciliations)
            blockingBootstraps=\(dashboardProbe.blockingNetworkCount)
            diskReads=\(diskIO.reads)
            diskWrites=\(diskIO.writes)
            realtimeChannels=\(SocialCacheProbe.realtimeSubscribed ? 1 : 0)
            surface.dashboard=\(dashboardSource)
            surface.feed=\(feedSource)
            surface.messages=\(messagesSource)
            surface.activity=\(activitySource)
            surface.rooms=\(roomsSource)
            surface.profile=\(profileSource)
            surface.tradeHistory=\(tradeHistorySource)
            surface.calendar=\(calendarSource)
            """

            logger.debug("\(coldSummary, privacy: .public)")
            logger.debug("\(performanceSummary, privacy: .public)")
            print(coldSummary)
            print(performanceSummary)
        }
    }

    private static func msSinceLaunch(_ marker: CFAbsoluteTime?) -> Int {
        guard let launchStartedAt, let marker else { return -1 }
        return Int((marker - launchStartedAt) * 1000)
    }
}
#else
nonisolated enum ColdLaunchSummaryProbe {
    static func markLaunchStarted() {}
    static func markLaunchSource(_ source: String) {}
    static func markAuthenticatedShell() {}
    static func markDashboardFirstRender(source: String) {}
    static func markPersistentRead() {}
    static func markFreshnessResult(_ result: String) {}
    static func resetForTesting() {}
}
#endif
