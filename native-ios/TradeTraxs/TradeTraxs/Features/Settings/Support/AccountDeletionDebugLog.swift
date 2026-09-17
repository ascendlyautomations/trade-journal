import Foundation
import OSLog

#if DEBUG
/// Account deletion milestones — never log tokens, codes, or secrets.
nonisolated enum AccountDeletionDebugLog {
    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "AccountDeletion"
    )

    static func confirmationPresented() {
        logger.debug("[AccountDeletion] confirmationPresented")
    }

    static func confirmed() {
        logger.debug("[AccountDeletion] confirmed")
    }

    static func requestStarted() {
        logger.debug("[AccountDeletion] requestStarted")
    }

    static func response(status: Int) {
        logger.debug("[AccountDeletion] response status=\(status, privacy: .public)")
    }

    static func appleRevocation(phase: String) {
        logger.debug("[AccountDeletion] appleRevocation \(phase, privacy: .public)")
    }

    static func accountDeleted() {
        logger.debug("[AccountDeletion] accountDeleted")
    }

    static func localTeardownStarted() {
        logger.debug("[AccountDeletion] localTeardownStarted")
    }

    static func completed() {
        logger.debug("[AccountDeletion] completed")
    }

    static func failed(reason: String) {
        logger.debug("[AccountDeletion] failed reason=\(reason, privacy: .public)")
    }
}
#endif
