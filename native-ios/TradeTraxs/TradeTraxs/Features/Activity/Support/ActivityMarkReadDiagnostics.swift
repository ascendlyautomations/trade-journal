import Foundation
import OSLog

nonisolated enum ActivityMarkReadDiagnostics {
    enum Outcome: String {
        case success
        case failure
        case skipped
    }

    static func logMarkAllRead(
        outcome: Outcome,
        unreadBefore: Int,
        rowCount: Int,
        errorType: String? = nil
    ) {
        #if DEBUG
        AppLog.notifications.debug(
            """
            activity.markAllRead outcome=\(outcome.rawValue, privacy: .public) \
            unreadBefore=\(unreadBefore, privacy: .public) \
            rowCount=\(rowCount, privacy: .public) \
            errorType=\(errorType ?? "none", privacy: .public)
            """
        )
        #endif
    }

    static func errorType(_ error: Error) -> String {
        if let app = error as? AppError {
            return String(describing: app)
        }
        return String(describing: type(of: error))
    }
}
