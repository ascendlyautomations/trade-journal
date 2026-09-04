import Foundation

/// Story-share DM / Trade Room payload — mirrors web `lib/storyShareMessage.ts`.
nonisolated enum StoryShareMessageSupport {
    static let messageType = "story_share"

    struct Payload: Equatable, Sendable {
        var storyID: String
        var storyImageURL: String
        var storyOwnerID: String
        var storyOwnerUsername: String?
    }

    static func encode(
        storyID: StoryID,
        imageURL: String,
        ownerID: ProfileID,
        ownerUsername: String?
    ) -> String {
        var payload: [String: Any] = [
            "story_id": storyID.rawValue,
            "story_image_url": imageURL.trimmingCharacters(in: .whitespacesAndNewlines),
            "story_owner_id": ownerID.rawValue,
        ]
        if let trimmedUsername = ownerUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedUsername.isEmpty
        {
            payload["story_owner_username"] = trimmedUsername
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }

    static func decode(from content: String?) -> Payload? {
        guard let raw = content?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        guard let storyID = json["story_id"] as? String,
              let storyImageURL = json["story_image_url"] as? String,
              let storyOwnerID = json["story_owner_id"] as? String
        else { return nil }

        // Story replies require `text`; shares must not be classified as replies.
        if json["text"] is String { return nil }

        let trimmedStoryID = storyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOwnerID = storyOwnerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedStoryID.isEmpty, !trimmedOwnerID.isEmpty else { return nil }

        let username = (json["story_owner_username"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Payload(
            storyID: trimmedStoryID,
            storyImageURL: storyImageURL.trimmingCharacters(in: .whitespacesAndNewlines),
            storyOwnerID: trimmedOwnerID,
            storyOwnerUsername: username?.isEmpty == false ? username : nil
        )
    }

    static func isStoryShare(type: String?, content: String?) -> Bool {
        if type?.lowercased() == messageType { return true }
        let normalizedType = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedType == nil || normalizedType == "text" {
            return decode(from: content) != nil
        }
        return false
    }

    static func previewText(from content: String?, emptyFallback: String = "Shared a story") -> String {
        guard let payload = decode(from: content) else {
            return emptyFallback
        }
        return cardTitle(payload: payload)
    }

    static func sanitizeInboxPreview(type: String?, content: String?) -> String? {
        if type?.lowercased() == messageType {
            return previewText(from: content)
        }
        if let content, decode(from: content) != nil {
            return previewText(from: content)
        }
        return content
    }

    static func cardTitle(payload: Payload) -> String {
        if let username = payload.storyOwnerUsername, !username.isEmpty {
            return "@\(username)'s story"
        }
        return "Shared a story"
    }

    /// Ephemeral seed for navigation — authoritative story still comes from feed fetch.
    static func provisionalStory(from payload: Payload) -> Story {
        Story(
            id: StoryID(payload.storyID),
            authorProfileID: ProfileID(payload.storyOwnerID),
            media: MediaReference(id: payload.storyImageURL, kind: .image, altText: nil),
            expiresAt: Date().addingTimeInterval(ActiveStorySemantics.window),
            createdAt: Date(),
            viewerHasSeen: true
        )
    }
}
