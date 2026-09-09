import Foundation
import OSLog

#if DEBUG
/// DEBUG instrumentation for session bootstrap warm-start decisions.
nonisolated enum SessionWarmStartProbe {
    struct Inspection: Sendable {
        var diskCacheExists: Bool
        var cacheAge: TimeInterval?
        var decodeSuccess: Bool
        var usable: Bool
        var reasonRejected: String?
    }

    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "SessionWarmStart"
    )

    static func inspectSessionDiskCache(viewerID: String) -> Inspection {
        guard let dir = cacheDirectoryURL() else {
            return Inspection(
                diskCacheExists: false,
                cacheAge: nil,
                decodeSuccess: false,
                usable: false,
                reasonRejected: "cacheDirectoryUnavailable"
            )
        }
        let fileURL = dir.appendingPathComponent("session-\(viewerID).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Inspection(
                diskCacheExists: false,
                cacheAge: nil,
                decodeSuccess: false,
                usable: false,
                reasonRejected: "diskCacheAbsent"
            )
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return Inspection(
                diskCacheExists: true,
                cacheAge: nil,
                decodeSuccess: false,
                usable: false,
                reasonRejected: "diskReadFailed"
            )
        }

        guard let blob = try? JSONDecoder().decode(BackendV2BootstrapDiskCache.SessionBlob.self, from: data) else {
            return Inspection(
                diskCacheExists: true,
                cacheAge: nil,
                decodeSuccess: false,
                usable: false,
                reasonRejected: "decodeFailed"
            )
        }

        guard blob.viewerID == viewerID else {
            return Inspection(
                diskCacheExists: true,
                cacheAge: nil,
                decodeSuccess: true,
                usable: false,
                reasonRejected: "viewerIDMismatch"
            )
        }

        guard blob.contractVersion == BackendV2Versioning.contractVersion else {
            return Inspection(
                diskCacheExists: true,
                cacheAge: Date().timeIntervalSince(blob.savedAt),
                decodeSuccess: true,
                usable: false,
                reasonRejected: "contractVersionMismatch"
            )
        }

        let age = Date().timeIntervalSince(blob.savedAt)
        if age > 24 * 60 * 60 {
            return Inspection(
                diskCacheExists: true,
                cacheAge: age,
                decodeSuccess: true,
                usable: false,
                reasonRejected: "hardExpired"
            )
        }

        return Inspection(
            diskCacheExists: true,
            cacheAge: age,
            decodeSuccess: true,
            usable: true,
            reasonRejected: nil
        )
    }

    static func log(
        _ inspection: Inspection,
        userID: String,
        forceNetwork: Bool,
        shellRenderedFromCache: Bool? = nil
    ) {
        let ageLabel: String = {
            guard let cacheAge = inspection.cacheAge else { return "n/a" }
            return String(format: "%.1fs", cacheAge)
        }()
        let shellLabel = shellRenderedFromCache.map { $0 ? "true" : "false" } ?? "n/a"
        logger.debug(
            """
            [SessionWarmStart] userID=\(userID, privacy: .public) \
            diskCacheExists=\(inspection.diskCacheExists, privacy: .public) \
            cacheAge=\(ageLabel, privacy: .public) \
            decodeSuccess=\(inspection.decodeSuccess, privacy: .public) \
            usable=\(inspection.usable, privacy: .public) \
            reasonRejected=\(inspection.reasonRejected ?? "none", privacy: .public) \
            forceNetwork=\(forceNetwork, privacy: .public) \
            shellRenderedFromCache=\(shellLabel, privacy: .public)
            """
        )
    }

    static func logShellRenderedFromCache(_ rendered: Bool, userID: String) {
        logger.debug(
            "[SessionWarmStart] userID=\(userID, privacy: .public) shellRenderedFromCache=\(rendered, privacy: .public)"
        )
    }

    static func warmStartTrace(_ step: String) {
        logger.debug("[WarmStartTrace] step=\(step, privacy: .public)")
    }

    private static func cacheDirectoryURL() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("BackendV2BootstrapCache", isDirectory: true)
    }
}
#else
nonisolated enum SessionWarmStartProbe {
    struct Inspection: Sendable {
        var diskCacheExists = false
        var cacheAge: TimeInterval?
        var decodeSuccess = false
        var usable = false
        var reasonRejected: String?
    }

    static func inspectSessionDiskCache(viewerID: String) -> Inspection { _ = viewerID; return Inspection() }
    static func log(_ inspection: Inspection, userID: String, forceNetwork: Bool, shellRenderedFromCache: Bool? = nil) {
        _ = (inspection, userID, forceNetwork, shellRenderedFromCache)
    }
    static func logShellRenderedFromCache(_ rendered: Bool, userID: String) { _ = (rendered, userID) }
    static func warmStartTrace(_ step: String) { _ = step }
}
#endif
