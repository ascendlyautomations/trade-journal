#if DEBUG
import Foundation
import os

/// DEBUG-only — upward scroll remounts vs session image restore (see ``FeedDisplayImageSessionCache``).
enum FeedScrollRowLifecycleDiagnostics {
    private static let log = Logger(subsystem: AppLog.subsystem, category: "FeedScrollRow")

    static func logRowAppear(entryID: String, restoredFromSessionCache: Bool) {
        log.debug(
            """
            rowAppear id=\(entryID, privacy: .public) \
            sessionImage=\(restoredFromSessionCache, privacy: .public)
            """
        )
    }
}
#endif
