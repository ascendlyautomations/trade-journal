import Foundation

#if DEBUG
nonisolated enum SocialRealtimeRepairDebugLog {
    static func disconnectObserved(activeRoutes: Int) {
        print("[SocialRealtimeRepair] disconnectObserved activeRoutes=\(activeRoutes)")
    }

    static func foregroundObserved(willResumeSocket: Bool) {
        print("[SocialRealtimeRepair] foregroundObserved willResumeSocket=\(willResumeSocket)")
    }

    static func reconnectObserved(activeRoutes: Int) {
        print("[SocialRealtimeRepair] reconnectObserved activeRoutes=\(activeRoutes)")
    }

    static func repairScheduled(reason: String, viewerGeneration: UInt64) {
        print("[SocialRealtimeRepair] repairScheduled reason=\(reason) generation=\(viewerGeneration)")
    }

    static func repairCoalesced(reason: String) {
        print("[SocialRealtimeRepair] repairCoalesced reason=\(reason)")
    }

    static func repairStarted(reasons: String, viewerGeneration: UInt64) {
        print("[SocialRealtimeRepair] repairStarted reasons=\(reasons) generation=\(viewerGeneration)")
    }

    static func domainRepairStarted(domain: String) {
        print("[SocialRealtimeRepair] domainRepairStarted domain=\(domain)")
    }

    static func domainSkippedFresh(domain: String, detail: String) {
        print("[SocialRealtimeRepair] domainSkippedFresh domain=\(domain) \(detail)")
    }

    static func domainRepairSuccess(domain: String, detail: String) {
        print("[SocialRealtimeRepair] domainRepairSuccess domain=\(domain) \(detail)")
    }

    static func domainRepairFailed(domain: String, detail: String) {
        print("[SocialRealtimeRepair] domainRepairFailed domain=\(domain) \(detail)")
    }

    static func staleGenerationRejected(context: String) {
        print("[SocialRealtimeRepair] staleGenerationRejected context=\(context)")
    }

    static func repairCompleted(
        elapsedMs: Int,
        requestCount: Int,
        domains: String,
        feedDelta: String?,
        activityMerged: Int?,
        inboxChanged: Bool?,
        followingDelta: String?
    ) {
        print(
            """
            [SocialRealtimeRepair] repairCompleted elapsedMs=\(elapsedMs) \
            requests=\(requestCount) domains=\(domains) \
            feed=\(feedDelta ?? "-") activity=\(activityMerged.map(String.init) ?? "-") \
            inbox=\(inboxChanged.map { $0 ? "changed" : "unchanged" } ?? "-") \
            following=\(followingDelta ?? "-")
            """
        )
    }
}
#endif
