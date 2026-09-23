import Foundation

#if DEBUG
enum RelationshipRealtimeDebugLog {
    static func relationshipPatch(
        kind: String,
        viewerID: String,
        followerID: String,
        followingID: String
    ) {
        print(
            """
            [RelationshipRealtime] relationshipPatch kind=\(kind) \
            viewer=\(viewerID) follower=\(followerID) following=\(followingID)
            """
        )
    }

    static func relationshipEchoIgnored(reason: String, detail: String) {
        print("[RelationshipRealtime] relationshipEchoIgnored reason=\(reason) \(detail)")
    }

    static func followingRouteSync(added: Int, removed: Int, complete: Bool) {
        print(
            """
            [RelationshipRealtime] followingRouteSync added=\(added) removed=\(removed) \
            completeSet=\(complete)
            """
        )
    }

    static func followRequestPatch(action: String, requesterID: String, targetID: String) {
        print(
            """
            [RelationshipRealtime] followRequestPatch action=\(action) \
            requester=\(requesterID) target=\(targetID)
            """
        )
    }

    static func networkFallback(reason: String) {
        print("[RelationshipRealtime] networkFallback reason=\(reason)")
    }
}
#endif
