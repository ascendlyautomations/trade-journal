import Foundation

#if DEBUG
nonisolated enum ProfileAnalyticsGRDBProbe {
    static func logRead(viewer: String, subject: String, revision: Int64, elapsedMs: Int) {
        print(
            "[ProfileAnalyticsGRDB][Read] viewer=\(viewer) subject=\(subject) " +
                "revision=\(revision) elapsedMs=\(elapsedMs)"
        )
    }

    static func logRender(viewer: String, subject: String, revision: Int64, source: String) {
        print(
            "[ProfileAnalyticsGRDB][Render] viewer=\(viewer) subject=\(subject) " +
                "revision=\(revision) source=\(source)"
        )
    }

    static func logMiss(viewer: String, subject: String) {
        print("[ProfileAnalyticsGRDB][Miss] viewer=\(viewer) subject=\(subject)")
    }

    static func logIngest(viewer: String, subject: String, revision: Int64, elapsedMs: Int) {
        print(
            "[ProfileAnalyticsGRDB][Ingest] viewer=\(viewer) subject=\(subject) " +
                "revision=\(revision) elapsedMs=\(elapsedMs)"
        )
    }

    static func logRevisionCurrent(viewer: String, subject: String, revision: Int64) {
        print(
            "[ProfileAnalyticsGRDB][RevisionCurrent] viewer=\(viewer) subject=\(subject) " +
                "revision=\(revision)"
        )
    }

    static func logRevisionStale(viewer: String, subject: String, cached: Int64, server: Int64) {
        print(
            "[ProfileAnalyticsGRDB][RevisionStale] viewer=\(viewer) subject=\(subject) " +
                "cached=\(cached) server=\(server)"
        )
    }

    static func logVisibilityReject(viewer: String, subject: String, expected: String, stored: String) {
        print(
            "[ProfileAnalyticsGRDB][VisibilityReject] viewer=\(viewer) subject=\(subject) " +
                "expected=\(expected) stored=\(stored)"
        )
    }

    static func logFallback(viewer: String, subject: String, reason: String) {
        print(
            "[ProfileAnalyticsGRDB][Fallback] viewer=\(viewer) subject=\(subject) reason=\(reason)"
        )
    }
}
#else
nonisolated enum ProfileAnalyticsGRDBProbe {
    static func logRead(viewer: String, subject: String, revision: Int64, elapsedMs: Int) {}
    static func logRender(viewer: String, subject: String, revision: Int64, source: String) {}
    static func logMiss(viewer: String, subject: String) {}
    static func logIngest(viewer: String, subject: String, revision: Int64, elapsedMs: Int) {}
    static func logRevisionCurrent(viewer: String, subject: String, revision: Int64) {}
    static func logRevisionStale(viewer: String, subject: String, cached: Int64, server: Int64) {}
    static func logVisibilityReject(viewer: String, subject: String, expected: String, stored: String) {}
    static func logFallback(viewer: String, subject: String, reason: String) {}
}
#endif
