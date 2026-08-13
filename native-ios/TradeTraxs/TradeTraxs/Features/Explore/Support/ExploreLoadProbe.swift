import Foundation
import OSLog

#if DEBUG
/// DEBUG-only Explore bootstrap timings — not used in Release.
enum ExploreLoadProbe {
    private static let log = Logger(subsystem: "com.tradetraxs.TradeTraxs", category: "ExploreLoad")

    struct Snapshot: Sendable {
        var requestCount: Int
        var blockingRequestCount: Int
        var timeToFirstUsefulRenderMS: Int
        var sectionsInitiallyLoaded: [String]
        var deferredSections: [String]
        var notes: String
    }

    private static var startedAt: Date?
    private static var requests = 0
    private static var blocking = 0

    static func beginBootstrap() {
        startedAt = Date()
        requests = 0
        blocking = 0
        log.debug("Explore bootstrap begin")
    }

    static func noteRequest(_ name: String, blocking: Bool = true) {
        requests += 1
        if blocking { self.blocking += 1 }
        log.debug("Explore request \(name, privacy: .public) blocking=\(blocking)")
    }

    static func firstUsefulRender(sections: [String]) -> Snapshot {
        let elapsed: Int
        if let startedAt {
            elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
        } else {
            elapsed = 0
        }
        let snap = Snapshot(
            requestCount: requests,
            blockingRequestCount: blocking,
            timeToFirstUsefulRenderMS: elapsed,
            sectionsInitiallyLoaded: sections,
            deferredSections: ["tradeActivityEnrichment"],
            notes: "Bootstrap = discoverableProfiles + popularRooms (+ following IDs)."
        )
        log.info(
            "Explore first useful render ms=\(snap.timeToFirstUsefulRenderMS) requests=\(snap.requestCount) blocking=\(snap.blockingRequestCount)"
        )
        return snap
    }
}
#endif
