import Foundation

#if DEBUG
nonisolated enum DashboardAnalyticsGRDBProbe {
    static func logRender(
        source: String,
        revision: Int64?,
        scope: String,
        preset: String,
        elapsedMs: Int
    ) {
        let rev = revision.map { String($0) } ?? "nil"
        print(
            "[DashboardGRDB][Render] source=\(source) revision=\(rev) scope=\(scope) " +
                "preset=\(preset) elapsedMs=\(elapsedMs)"
        )
    }

    static func logFallback(reason: String) {
        print("[DashboardGRDB][Fallback] reason=\(reason)")
    }

    static func logNetworkAvoided(reason: String) {
        print("[DashboardGRDB][NetworkAvoided] reason=\(reason)")
    }

    static func logReconcile(localRevision: Int64?, serverRevision: Int64?, changed: Bool) {
        let local = localRevision.map { String($0) } ?? "nil"
        let server = serverRevision.map { String($0) } ?? "nil"
        print(
            "[DashboardGRDB][Reconcile] localRevision=\(local) serverRevision=\(server) " +
                "changed=\(changed)"
        )
    }

    static func logAccountCharts(
        account: String,
        state: String,
        revision: Int64?
    ) {
        let rev = revision.map { String($0) } ?? "nil"
        print(
            "[DashboardGRDB][AccountCharts] account=\(account) state=\(state) revision=\(rev)"
        )
    }
}
#else
nonisolated enum DashboardAnalyticsGRDBProbe {
    static func logRender(
        source: String,
        revision: Int64?,
        scope: String,
        preset: String,
        elapsedMs: Int
    ) {}
    static func logFallback(reason: String) {}
    static func logNetworkAvoided(reason: String) {}
    static func logReconcile(localRevision: Int64?, serverRevision: Int64?, changed: Bool) {}
    static func logAccountCharts(account: String, state: String, revision: Int64?) {}
}
#endif
