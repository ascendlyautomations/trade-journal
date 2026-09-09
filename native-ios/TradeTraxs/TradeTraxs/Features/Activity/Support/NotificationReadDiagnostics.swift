import Foundation
import OSLog

#if DEBUG
enum NotificationReadDiagnostics {
    static func logBulkMarkRead(ids: Int, requests: Int, dtMs: Int) {
        AppLog.general.debug(
            "[NotificationRead] ids=\(ids, privacy: .public) requests=\(requests, privacy: .public) dtMs=\(dtMs, privacy: .public)"
        )
    }
}
#else
enum NotificationReadDiagnostics {
    static func logBulkMarkRead(ids: Int, requests: Int, dtMs: Int) {}
}
#endif
