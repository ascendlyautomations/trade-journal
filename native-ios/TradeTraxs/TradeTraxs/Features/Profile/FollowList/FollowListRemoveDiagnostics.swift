import Foundation
import os

/// Temporary stage logging for Profile → Followers → Remove (filter Console on `followList.remove`).
enum FollowListRemoveDiagnostics {
    #if DEBUG
    private static let log = Logger(subsystem: "com.tradetraxs.app", category: "followList.remove")
    #endif

    static func confirmInvoked(followerID: String, ownerID: String) {
        #if DEBUG
        log.info("confirm follower=\(followerID, privacy: .public) owner=\(ownerID, privacy: .public)")
        #endif
    }

    static func guardFailed(_ reason: String) {
        #if DEBUG
        log.error("guard failed reason=\(reason, privacy: .public)")
        #endif
    }

    static func optimistic(beforeCount: Int, afterCount: Int, followerID: String) {
        #if DEBUG
        log.info(
            "optimistic follower=\(followerID, privacy: .public) before=\(beforeCount, privacy: .public) after=\(afterCount, privacy: .public)"
        )
        #endif
    }

    static func apiStarted(followerID: String, ownerID: String) {
        #if DEBUG
        log.info("api delete follower=\(followerID, privacy: .public) owner=\(ownerID, privacy: .public)")
        #endif
    }

    static func apiSucceeded(followerID: String) {
        #if DEBUG
        log.info("api delete succeeded follower=\(followerID, privacy: .public)")
        #endif
    }

    static func apiFailed(followerID: String, message: String) {
        #if DEBUG
        log.error("api delete failed follower=\(followerID, privacy: .public) message=\(message, privacy: .public)")
        #endif
    }

    static func rollback(followerID: String, restoredCount: Int) {
        #if DEBUG
        log.info(
            "rollback follower=\(followerID, privacy: .public) restoredCount=\(restoredCount, privacy: .public)"
        )
        #endif
    }

    static func performLoadAppliedList(count: Int, source: String) {
        #if DEBUG
        log.info("performLoad list count=\(count, privacy: .public) source=\(source, privacy: .public)")
        #endif
    }
}