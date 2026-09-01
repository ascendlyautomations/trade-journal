import Foundation
import OSLog

#if DEBUG
nonisolated enum AddTradeLoadProbe {
    private static let log = Logger(subsystem: AppLog.subsystem, category: "AddTradeLoad")

    struct Snapshot: Sendable {
        var requestCount: Int
        var blockingRequestCount: Int
        var timeToUsableFormMS: Int
        var loadedOnOpen: [String]
        var deferred: [String]
    }

    nonisolated(unsafe) private static var startedAt: Date?
    nonisolated(unsafe) private static var requests = 0
    nonisolated(unsafe) private static var blocking = 0

    static func begin() {
        startedAt = Date()
        requests = 0
        blocking = 0
        log.debug("Add Trade open begin")
    }

    static func noteRequest(_ name: String, blocking: Bool = true) {
        requests += 1
        if blocking { self.blocking += 1 }
        log.debug("Add Trade request \(name, privacy: .public)")
    }

    static func usableForm(loaded: [String]) -> Snapshot {
        let ms: Int
        if let startedAt {
            ms = Int(Date().timeIntervalSince(startedAt) * 1000)
        } else {
            ms = 0
        }
        let snap = Snapshot(
            requestCount: requests,
            blockingRequestCount: blocking,
            timeToUsableFormMS: ms,
            loadedOnOpen: loaded,
            deferred: ["screenshotUpload", "publicPostInsert"]
        )
        log.info(
            "Add Trade usable form ms=\(snap.timeToUsableFormMS) requests=\(snap.requestCount)"
        )
        return snap
    }
}
#endif
