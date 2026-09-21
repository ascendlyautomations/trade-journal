import Foundation

#if DEBUG
nonisolated enum CalendarAnalyticsGRDBProbe {
    static func logRender(
        source: String,
        range: String,
        account: String,
        mode: String,
        localState: AnalyticsLocalReadState,
        revision: Int64?,
        elapsedMs: Int
    ) {
        let rev = revision.map { String($0) } ?? "nil"
        print(
            "[CalendarGRDB][Render] source=\(source) range=\(range) account=\(account) " +
                "mode=\(mode) localState=\(localState) revision=\(rev) elapsedMs=\(elapsedMs)"
        )
    }

    static func logFallback(reason: String) {
        print("[CalendarGRDB][Fallback] reason=\(reason)")
    }

    static func logNetworkAvoided(reason: String) {
        print("[CalendarGRDB][NetworkAvoided] reason=\(reason)")
    }

    static func logReconcile(reason: String, range: String) {
        print("[CalendarGRDB][Reconcile] reason=\(reason) range=\(range)")
    }
}
#else
nonisolated enum CalendarAnalyticsGRDBProbe {
    static func logRender(
        source: String,
        range: String,
        account: String,
        mode: String,
        localState: AnalyticsLocalReadState,
        revision: Int64?,
        elapsedMs: Int
    ) {}
    static func logFallback(reason: String) {}
    static func logNetworkAvoided(reason: String) {}
    static func logReconcile(reason: String, range: String) {}
}
#endif
