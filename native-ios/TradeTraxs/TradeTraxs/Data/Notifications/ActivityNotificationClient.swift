import Foundation
import OSLog

/// Wire JSON for `/api/notifications/{follow,follow-request,like,comment}`.
/// Keys match the web BFF (`followingId`, `targetId`, `commentId`, `target.kind`).
nonisolated enum ActivityNotificationJSON {
    struct Follow: Encodable, Sendable {
        var followingId: String
    }

    struct FollowRequest: Encodable, Sendable {
        var targetId: String
    }

    struct Comment: Encodable, Sendable {
        var commentId: String
    }

    struct LikeEnvelope: Encodable, Sendable {
        var target: LikeTarget
    }

    enum LikeTarget: Encodable, Sendable {
        case trade(tradeId: String)
        case post(postId: String, tradeId: String?)
        case profilePost(profilePostId: String)
        case achievementPost(achievementPostId: String)
        case reel(reelId: String)
        case comment(
            commentId: String,
            commentSource: String,
            postId: String? = nil,
            tradeId: String? = nil,
            profilePostId: String? = nil,
            achievementPostId: String? = nil,
            reelId: String? = nil
        )

        private enum CodingKeys: String, CodingKey {
            case kind
            case tradeId
            case postId
            case profilePostId
            case achievementPostId
            case reelId
            case commentId
            case commentSource
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .trade(let tradeId):
                try container.encode("trade", forKey: .kind)
                try container.encode(tradeId, forKey: .tradeId)
            case .post(let postId, let tradeId):
                try container.encode("post", forKey: .kind)
                try container.encode(postId, forKey: .postId)
                try container.encodeIfPresent(tradeId, forKey: .tradeId)
            case .profilePost(let profilePostId):
                try container.encode("profile_post", forKey: .kind)
                try container.encode(profilePostId, forKey: .profilePostId)
            case .achievementPost(let achievementPostId):
                try container.encode("achievement_post", forKey: .kind)
                try container.encode(achievementPostId, forKey: .achievementPostId)
            case .reel(let reelId):
                try container.encode("reel", forKey: .kind)
                try container.encode(reelId, forKey: .reelId)
            case .comment(
                let commentId,
                let commentSource,
                let postId,
                let tradeId,
                let profilePostId,
                let achievementPostId,
                let reelId
            ):
                try container.encode("comment", forKey: .kind)
                try container.encode(commentId, forKey: .commentId)
                try container.encode(commentSource, forKey: .commentSource)
                try container.encodeIfPresent(postId, forKey: .postId)
                try container.encodeIfPresent(tradeId, forKey: .tradeId)
                try container.encodeIfPresent(profilePostId, forKey: .profilePostId)
                try container.encodeIfPresent(achievementPostId, forKey: .achievementPostId)
                try container.encodeIfPresent(reelId, forKey: .reelId)
            }
        }

        static func content(_ target: InteractionTarget, contentID: String) -> LikeTarget {
            switch target.kind {
            case .trade:
                return .trade(tradeId: contentID)
            case .feedPost:
                return .post(postId: contentID, tradeId: nil)
            case .profilePost:
                return .profilePost(profilePostId: contentID)
            case .achievement:
                return .achievementPost(achievementPostId: contentID)
            case .reel:
                return .reel(reelId: contentID)
            }
        }

        static func commentLike(
            commentID: String,
            source: CommentLikeSource,
            parent: InteractionTarget? = nil
        ) -> LikeTarget {
            var postId: String?
            var tradeId: String?
            var profilePostId: String?
            var achievementPostId: String?
            var reelId: String?
            if let parent {
                switch parent.kind {
                case .feedPost: postId = parent.id
                case .trade: tradeId = parent.id
                case .profilePost: profilePostId = parent.id
                case .achievement: achievementPostId = parent.id
                case .reel: reelId = parent.id
                }
            }
            return .comment(
                commentId: commentID,
                commentSource: source.rawValue,
                postId: postId,
                tradeId: tradeId,
                profilePostId: profilePostId,
                achievementPostId: achievementPostId,
                reelId: reelId
            )
        }
    }
}

/// Mirrors web Activity notify after follows, likes, and comments.
///
/// Activity rows + APNs are created server-side (`emitActivityNotification`).
/// Failures are logged and never thrown to the social write path.
nonisolated struct ActivityNotificationClient: Sendable {
    private let transport: SupabaseTransport?

    init(transport: SupabaseTransport?) {
        self.transport = transport
    }

    func notifyFollow(followingID: String) async {
        await send(
            path: "/api/notifications/follow",
            method: .post,
            body: ActivityNotificationJSON.Follow(followingId: followingID),
            id: followingID,
            label: "follow"
        )
    }

    func removeFollow(followingID: String) async {
        await send(
            path: "/api/notifications/follow",
            method: .delete,
            body: ActivityNotificationJSON.Follow(followingId: followingID),
            id: followingID,
            label: "follow-remove"
        )
    }

    func notifyFollowRequest(targetID: String) async {
        await send(
            path: "/api/notifications/follow-request",
            method: .post,
            body: ActivityNotificationJSON.FollowRequest(targetId: targetID),
            id: targetID,
            label: "follow-request"
        )
    }

    func removeFollowRequest(targetID: String) async {
        await send(
            path: "/api/notifications/follow-request",
            method: .delete,
            body: ActivityNotificationJSON.FollowRequest(targetId: targetID),
            id: targetID,
            label: "follow-request-remove"
        )
    }

    func notifyLike(_ target: ActivityNotificationJSON.LikeTarget) async {
        await send(
            path: "/api/notifications/like",
            method: .post,
            body: ActivityNotificationJSON.LikeEnvelope(target: target),
            id: likeTargetID(target),
            label: "like"
        )
    }

    func notifyComment(commentID: String) async {
        await send(
            path: "/api/notifications/comment",
            method: .post,
            body: ActivityNotificationJSON.Comment(commentId: commentID),
            id: commentID,
            label: "comment"
        )
    }

    private func send<Body: Encodable>(
        path: String,
        method: HTTPMethod,
        body: Body,
        id: String,
        label: String
    ) async {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let transport else {
            AppLog.notifications.error("Activity \(label, privacy: .public) notify skipped: network transport unavailable")
            return
        }

        do {
            let data = try transport.encodeJSON(body)
            let response = try await transport.send(
                host: .bff,
                path: path,
                method: method,
                body: data,
                requiresAuthentication: true
            )
            guard (200 ... 299).contains(response.statusCode) else {
                let snippet = String(data: response.data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(200) ?? ""
                AppLog.notifications.error(
                    """
                    Activity \(label, privacy: .public) notify failed \
                    status=\(response.statusCode, privacy: .public) \
                    id=\(trimmed, privacy: .public) \
                    body=\(String(snippet), privacy: .public)
                    """
                )
                return
            }
            AppLog.notifications.info(
                "Activity \(label, privacy: .public) notify ok id=\(trimmed, privacy: .public)"
            )
        } catch {
            AppLog.notifications.error(
                "Activity \(label, privacy: .public) notify error: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func likeTargetID(_ target: ActivityNotificationJSON.LikeTarget) -> String {
        switch target {
        case .trade(let tradeId):
            return tradeId
        case .post(let postId, _):
            return postId
        case .profilePost(let profilePostId):
            return profilePostId
        case .achievementPost(let achievementPostId):
            return achievementPostId
        case .reel(let reelId):
            return reelId
        case .comment(let commentId, _, _, _, _, _, _):
            return commentId
        }
    }
}
