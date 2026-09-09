import Foundation

#if DEBUG
/// Lightweight timing for Feed → All progressive row publish vs media hydration.
nonisolated enum FeedProgressiveRenderProbe {
    nonisolated(unsafe) private static var bootstrapDecodedAt: CFAbsoluteTime?
    nonisolated(unsafe) private static var rowsPublishedAt: CFAbsoluteTime?

    static func resetForTesting() {
        bootstrapDecodedAt = nil
        rowsPublishedAt = nil
    }

    static func recordBootstrapDecoded(count: Int) {
        bootstrapDecodedAt = CFAbsoluteTimeGetCurrent()
        print("[FeedProgressiveRender] bootstrapDecoded count=\(count)")
    }

    static func recordRowsPublished(count: Int) {
        let now = CFAbsoluteTimeGetCurrent()
        rowsPublishedAt = now
        let dtMs: Int
        if let start = bootstrapDecodedAt {
            dtMs = Int((now - start) * 1000)
        } else {
            dtMs = 0
        }
        print("[FeedProgressiveRender] rowsPublished count=\(count) dtMs=\(dtMs)")
    }

    static func dtFromRowsPublishedMs() -> Int? {
        guard let rowsPublishedAt else { return nil }
        return Int((CFAbsoluteTimeGetCurrent() - rowsPublishedAt) * 1000)
    }
}

nonisolated enum FeedMediaReadyProbe {
    nonisolated(unsafe) private static var loggedKeys: Set<String> = []

    static func resetForTesting() {
        loggedKeys = []
    }

    static func log(itemID: String, kind: String, source: String) {
        let key = "\(itemID)|\(kind)|\(source)"
        guard loggedKeys.insert(key).inserted else { return }
        let dt = FeedProgressiveRenderProbe.dtFromRowsPublishedMs() ?? -1
        print(
            "[FeedMediaReady] itemID=\(itemID) kind=\(kind) source=\(source) dtFromRowsPublishedMs=\(dt)"
        )
    }
}
#else
nonisolated enum FeedProgressiveRenderProbe {
    static func resetForTesting() {}
    static func recordBootstrapDecoded(count: Int) {}
    static func recordRowsPublished(count: Int) {}
    static func dtFromRowsPublishedMs() -> Int? { nil }
}

nonisolated enum FeedMediaReadyProbe {
    static func resetForTesting() {}
    static func log(itemID: String, kind: String, source: String) {}
}
#endif
