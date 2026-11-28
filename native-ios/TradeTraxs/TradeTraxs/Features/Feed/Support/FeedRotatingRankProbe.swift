#if DEBUG
import Foundation

/// DEBUG diagnostics for rotating feed rank + impressions.
nonisolated enum FeedRotatingRankProbe {
    static func impressionQualified(kind: String, contentID: String) {
        print("[FeedRotating] impression.qualified kind=\(kind) id=\(contentID)")
    }

    static func impressionUploaded(count: Int, viewerID: String) {
        print("[FeedRotating] impression.uploaded count=\(count) viewer=\(viewerID)")
    }

    static func impressionUploadFailed(count: Int, error: Error) {
        print("[FeedRotating] impression.uploadFailed count=\(count) error=\(error)")
    }

    static func rankSessionBegan(scope: String, filter: String, sessionID: String) {
        print("[FeedRotating] rank.session scope=\(scope) filter=\(filter) session=\(sessionID)")
    }

    static func v2Fallback(reason: String) {
        print("[FeedRotating] rank.v1Fallback reason=\(reason)")
    }
}
#else
import Foundation

nonisolated enum FeedRotatingRankProbe {
    static func impressionQualified(kind: String, contentID: String) {}
    static func impressionUploaded(count: Int, viewerID: String) {}
    static func impressionUploadFailed(count: Int, error: Error) {}
    static func rankSessionBegan(scope: String, filter: String, sessionID: String) {}
    static func v2Fallback(reason: String) {}
}
#endif