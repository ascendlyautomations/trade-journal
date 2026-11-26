import Foundation

nonisolated enum StoryInsightsMapper {
    private struct Envelope: Decodable {
        var data: Payload?
    }

    private struct Payload: Decodable {
        var story_id: String?
        var view_count: Int?
        var like_count: Int?
        var reply_count: Int?
        var viewers: [ViewerRow]?
        var likers: [LikerRow]?
        var repliers: [ReplierRow]?
    }

    private struct ViewerRow: Decodable {
        var id: String?
        var username: String?
        var display_name: String?
        var avatar_url: String?
        var viewed_at: String?
        var liked: Bool?
        var replied: Bool?
    }

    private struct LikerRow: Decodable {
        var id: String?
        var username: String?
        var display_name: String?
        var avatar_url: String?
        var liked_at: String?
        var liked: Bool?
    }

    private struct ReplierRow: Decodable {
        var id: String?
        var username: String?
        var display_name: String?
        var avatar_url: String?
        var replied_at: String?
        var replied: Bool?
    }

    static func decode(from data: Data) throws -> StoryInsights {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let payload = envelope.data else {
            throw AppError.unknown(message: "Story insights response missing data")
        }
        guard let storyRaw = payload.story_id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !storyRaw.isEmpty
        else {
            throw AppError.unknown(message: "Story insights response missing story id")
        }

        var likedByID: Set<String> = []
        for row in payload.likers ?? [] {
            if let id = row.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                likedByID.insert(id)
            }
        }

        var repliedByID: Set<String> = []
        for row in payload.repliers ?? [] {
            if let id = row.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                repliedByID.insert(id)
            }
        }

        var viewers: [StoryInsightsViewer] = (payload.viewers ?? []).compactMap {
            mapViewer($0, likedFallback: likedByID, repliedFallback: repliedByID)
        }
        var knownIDs = Set(viewers.map(\.id.rawValue))

        for row in payload.likers ?? [] {
            guard let viewer = mapViewerFromLiker(row), !knownIDs.contains(viewer.id.rawValue) else { continue }
            viewers.append(viewer)
            knownIDs.insert(viewer.id.rawValue)
        }

        for row in payload.repliers ?? [] {
            guard let viewer = mapViewerFromReplier(row, likedFallback: likedByID),
                  !knownIDs.contains(viewer.id.rawValue)
            else { continue }
            viewers.append(viewer)
            knownIDs.insert(viewer.id.rawValue)
        }

        for index in viewers.indices where repliedByID.contains(viewers[index].id.rawValue) {
            viewers[index].replied = true
        }

        return StoryInsights(
            storyID: StoryID(storyRaw),
            viewCount: payload.view_count ?? 0,
            likeCount: payload.like_count ?? 0,
            replyCount: payload.reply_count ?? 0,
            viewers: viewers
        )
    }

    private static func mapViewer(
        _ row: ViewerRow,
        likedFallback: Set<String>,
        repliedFallback: Set<String>
    ) -> StoryInsightsViewer? {
        guard let idRaw = row.id?.trimmingCharacters(in: .whitespacesAndNewlines), !idRaw.isEmpty else {
            return nil
        }
        let username = ProfileUsernamePolicy.resolvedPublicUsername(
            primary: row.username ?? "",
            profileID: ProfileID(idRaw),
            fallback: "trader"
        )
        let displayName = resolvedDisplayName(displayName: row.display_name, username: username)
        let liked = row.liked ?? likedFallback.contains(idRaw)
        let replied = row.replied ?? repliedFallback.contains(idRaw)
        return StoryInsightsViewer(
            id: ProfileID(idRaw),
            username: username,
            displayName: displayName,
            avatarURL: row.avatar_url,
            viewedAt: ISO8601.date(from: row.viewed_at),
            liked: liked,
            replied: replied
        )
    }

    private static func mapViewerFromLiker(_ row: LikerRow) -> StoryInsightsViewer? {
        guard let idRaw = row.id?.trimmingCharacters(in: .whitespacesAndNewlines), !idRaw.isEmpty else {
            return nil
        }
        let username = ProfileUsernamePolicy.resolvedPublicUsername(
            primary: row.username ?? "",
            profileID: ProfileID(idRaw),
            fallback: "trader"
        )
        let displayName = resolvedDisplayName(displayName: row.display_name, username: username)
        return StoryInsightsViewer(
            id: ProfileID(idRaw),
            username: username,
            displayName: displayName,
            avatarURL: row.avatar_url,
            viewedAt: ISO8601.date(from: row.liked_at),
            liked: true,
            replied: false
        )
    }

    private static func mapViewerFromReplier(
        _ row: ReplierRow,
        likedFallback: Set<String>
    ) -> StoryInsightsViewer? {
        guard let idRaw = row.id?.trimmingCharacters(in: .whitespacesAndNewlines), !idRaw.isEmpty else {
            return nil
        }
        let username = ProfileUsernamePolicy.resolvedPublicUsername(
            primary: row.username ?? "",
            profileID: ProfileID(idRaw),
            fallback: "trader"
        )
        let displayName = resolvedDisplayName(displayName: row.display_name, username: username)
        return StoryInsightsViewer(
            id: ProfileID(idRaw),
            username: username,
            displayName: displayName,
            avatarURL: row.avatar_url,
            viewedAt: ISO8601.date(from: row.replied_at),
            liked: likedFallback.contains(idRaw),
            replied: true
        )
    }

    private static func resolvedDisplayName(displayName: String?, username: String) -> String {
        if let sanitized = ProfileIdentitySanitizer.sanitizedPublicField(displayName), !sanitized.isEmpty {
            return sanitized
        }
        return username
    }
}