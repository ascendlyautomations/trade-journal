import Foundation
import OSLog

#if DEBUG
enum VaultLoadDiagnostics {
    static func logCacheHit(items: Int, folders: Int) {
        AppLog.general.debug(
            "[Vault] load source=cache items=\(items, privacy: .public) folders=\(folders, privacy: .public)"
        )
    }

    static func logRefresh(reason: String) {
        AppLog.general.debug("[Vault] refresh reason=\(reason, privacy: .public)")
    }

    static func logFirstRenderable(dtMs: Int) {
        AppLog.general.debug("[Vault] firstRenderable dtMs=\(dtMs, privacy: .public)")
    }
}
#else
enum VaultLoadDiagnostics {
    static func logCacheHit(items: Int, folders: Int) {}
    static func logRefresh(reason: String) {}
    static func logFirstRenderable(dtMs: Int) {}
}
#endif
