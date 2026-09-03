import Foundation

/// Canonical inbox activity merge + ordering — ports web `conversationInboxSync` rules.
///
/// Latest preview/timestamp/order derive from the newest canonical message regardless of sender.
/// Unread count is owned by ``MessagesInboxStore`` / server unread RPC — never inferred here.
nonisolated enum ConversationInboxActivity {
    /// Preview text for an inbox row from a domain message.
    static func preview(for message: Message) -> String {
        if message.kind == .system { return "System message" }
        if message.kind == .tradeShare { return "Shared a trade" }
        if message.kind == .voice { return "Voice message" }
        if message.kind == .storyReply {
            return StoryReplyMessageSupport.previewText(from: message.body)
        }
        if let body = message.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            if StoryReplyMessageSupport.decode(from: body) != nil {
                return StoryReplyMessageSupport.previewText(from: body)
            }
            return body
        }
        if !message.attachments.isEmpty {
            if message.attachments.first?.tradeID != nil { return "Shared a trade" }
            if message.kind == .voice || message.attachments.first?.media.kind == .audio {
                return "Voice message"
            }
            return "Photo"
        }
        return "New message"
    }

    /// True when `incoming` message should replace `existing` for preview ordering.
    static func isMessageNewer(_ incoming: Message, than existing: Message) -> Bool {
        if incoming.createdAt != existing.createdAt {
            return incoming.createdAt > existing.createdAt
        }
        return incoming.id.rawValue > existing.id.rawValue
    }

    /// True when `incoming` should replace `existing` preview/activity fields.
    static func isIncomingActivityNewer(_ incoming: Conversation, than existing: Conversation) -> Bool {
        let incomingAt = incoming.lastMessageAt
        let existingAt = existing.lastMessageAt
        if incomingAt == nil, existingAt != nil {
            return false
        }
        if incomingAt != nil, existingAt == nil {
            return true
        }
        guard let incomingAt, let existingAt else {
            return false
        }
        if incomingAt != existingAt {
            return incomingAt > existingAt
        }
        let incomingID = incoming.lastMessageID?.rawValue ?? ""
        let existingID = existing.lastMessageID?.rawValue ?? ""
        if !existingID.isEmpty, incomingID.isEmpty {
            return false
        }
        if !incomingID.isEmpty, existingID.isEmpty {
            return true
        }
        if incomingID != existingID {
            return incomingID > existingID
        }
        if incoming.updatedAt != existing.updatedAt {
            return incoming.updatedAt > existing.updatedAt
        }
        return false
    }

    /// Merge bootstrap/cache rows — never downgrade preview or activity timestamp.
    static func mergeConversations(existing: Conversation, incoming: Conversation) -> Conversation {
        var merged = incoming
        merged.isPinned = existing.isPinned || incoming.isPinned
        merged.isMuted = existing.isMuted || incoming.isMuted

        if isIncomingActivityNewer(incoming, than: existing) {
            if merged.lastMessageID == nil {
                merged.lastMessageID = existing.lastMessageID
            }
            if merged.lastMessagePreview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
               let existingPreview = existing.lastMessagePreview,
               !existingPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                merged.lastMessagePreview = existingPreview
            }
            return merged
        }

        merged.lastMessagePreview = existing.lastMessagePreview
        merged.lastMessageAt = existing.lastMessageAt
        merged.lastMessageID = existing.lastMessageID
        merged.updatedAt = max(existing.updatedAt, incoming.updatedAt)
        return merged
    }

    /// Apply a confirmed viewer send — always wins over equal/stale inbox rows.
    static func applyingConfirmedSendActivity(
        to conversation: Conversation,
        message: Message
    ) -> Conversation {
        var patch = conversation
        patch.lastMessagePreview = preview(for: message)
        patch.lastMessageAt = message.createdAt
        patch.lastMessageID = message.id
        patch.updatedAt = max(conversation.updatedAt, message.createdAt)
        return patch
    }

    /// Apply a confirmed message activity patch onto a conversation row.
    static func applyingMessageActivity(
        to conversation: Conversation,
        message: Message
    ) -> Conversation? {
        var patch = conversation
        patch.lastMessagePreview = preview(for: message)
        patch.lastMessageAt = message.createdAt
        patch.lastMessageID = message.id
        patch.updatedAt = message.createdAt

        guard isIncomingActivityNewer(patch, than: conversation) else {
            return nil
        }
        return patch
    }

    /// Web `sortConversationsDesc` + deterministic tie-breakers for equal timestamps.
    static func sortConversations(
        _ items: [Conversation],
        pinned: Set<ConversationID>
    ) -> [Conversation] {
        items.sorted { lhs, rhs in
            let lp = pinned.contains(lhs.id) || lhs.isPinned
            let rp = pinned.contains(rhs.id) || rhs.isPinned
            if lp != rp { return lp && !rp }

            let lat = lhs.lastMessageAt ?? .distantPast
            let rat = rhs.lastMessageAt ?? .distantPast
            if lat != rat { return lat > rat }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            let lid = lhs.lastMessageID?.rawValue ?? ""
            let rid = rhs.lastMessageID?.rawValue ?? ""
            if lid != rid { return lid > rid }

            return lhs.id.rawValue > rhs.id.rawValue
        }
    }
}
