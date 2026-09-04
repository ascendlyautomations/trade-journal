import Foundation

/// Story-reply DM payload — mirrors web `lib/storyReplyMessage.ts`.
nonisolated enum StoryReplyMessageSupport {
    static let messageType = "story_reply"

    struct Payload: Equatable, Sendable {
        var text: String
        var storyID: String
        var storyImageURL: String
        var storyOwnerID: String
        var storyOwnerUsername: String?
    }

    static func decode(from content: String?) -> Payload? {
        guard let raw = content?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        guard let storyID = json["story_id"] as? String,
              let storyImageURL = json["story_image_url"] as? String,
              let storyOwnerID = json["story_owner_id"] as? String,
              let text = json["text"] as? String
        else { return nil }

        let trimmedStoryID = storyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOwnerID = storyOwnerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedStoryID.isEmpty, !trimmedOwnerID.isEmpty else { return nil }

        let username = (json["story_owner_username"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Payload(
            text: text,
            storyID: trimmedStoryID,
            storyImageURL: storyImageURL.trimmingCharacters(in: .whitespacesAndNewlines),
            storyOwnerID: trimmedOwnerID,
            storyOwnerUsername: username?.isEmpty == false ? username : nil
        )
    }

    static func isStoryReply(type: String?, content: String?) -> Bool {
        if type?.lowercased() == messageType { return true }
        let normalizedType = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedType == nil || normalizedType == "text" {
            return decode(from: content) != nil
        }
        return false
    }

    static func previewText(from content: String?, emptyFallback: String = "Replied to a story") -> String {
        guard let payload = decode(from: content) else {
            let trimmed = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? emptyFallback : trimmed
        }
        let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? emptyFallback : trimmed
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

    static func contextLabel(payload: Payload, viewerProfileID: ProfileID?) -> String {
        if let viewerProfileID, payload.storyOwnerID == viewerProfileID.rawValue {
            return "Replied to your story"
        }
        if let username = payload.storyOwnerUsername, !username.isEmpty {
            return "Replied to @\(username)'s story"
        }
        return "Replied to a story"
    }

    static func replyText(from payload: Payload) -> String? {
        let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
