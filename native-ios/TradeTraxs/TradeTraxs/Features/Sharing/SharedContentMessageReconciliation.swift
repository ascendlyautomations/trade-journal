import Foundation

/// Removes or rewrites DM / Trade Room rows when a structured share target no longer exists.
nonisolated enum SharedContentMessageReconciliation {
    struct Result: Sendable {
        var messages: [Message]
        var removedIDs: Set<MessageID>
        var didChange: Bool
    }

    static func apply(
        to messages: [Message],
        unavailableKeys: Set<String>,
        sharedPosts: [PostID: Post] = [:]
    ) -> Result {
        guard !unavailableKeys.isEmpty, !messages.isEmpty else {
            return Result(messages: messages, removedIDs: [], didChange: false)
        }

        var removedIDs: Set<MessageID> = []
        var output: [Message] = []
        output.reserveCapacity(messages.count)
        var didChange = false

        for message in messages {
            guard primaryShareUnavailable(message, unavailableKeys: unavailableKeys, sharedPosts: sharedPosts) else {
                output.append(message)
                continue
            }

            if shouldRemoveEntireMessage(message) {
                removedIDs.insert(message.id)
                didChange = true
                continue
            }

            if let stripped = stripStructuredShare(from: message) {
                if stripped != message {
                    didChange = true
                }
                output.append(stripped)
            } else {
                removedIDs.insert(message.id)
                didChange = true
            }
        }

        return Result(messages: output, removedIDs: removedIDs, didChange: didChange)
    }

    static func unavailableKeys(
        for message: Message,
        unavailableKeys: Set<String>,
        sharedPosts: [PostID: Post] = [:]
    ) -> Bool {
        primaryShareUnavailable(message, unavailableKeys: unavailableKeys, sharedPosts: sharedPosts)
    }

    static func stableKeys(forDeletedTradeID tradeID: TradeID) -> Set<String> {
        [SharedContentReference.trade(tradeID).stableKey]
    }

    static func stableKeys(forDeletedPostID postID: PostID) -> Set<String> {
        [
            SharedContentReference.feedPost(postID).stableKey,
            SharedContentReference.profilePost(postID).stableKey,
            SharedContentReference.achievementPost(postID).stableKey,
        ]
    }

    static func stableKeys(forDeletedReelID reelID: ReelID) -> Set<String> {
        [SharedContentReference.reel(reelID).stableKey]
    }

    @MainActor
    static func supplementaryUnavailableKeys(
        afterAchievementDeleted achievementID: AchievementID,
        messages: [Message],
        sharedAchievements: [AchievementID: Achievement],
        detailCache: DetailPresentationCache
    ) -> Set<String> {
        var keys: Set<String> = []
        for message in messages {
            guard case .achievementPost(let postReference) = message.sharedContent else { continue }
            if let resolved = SharedContentEntityPresentation.resolvedAchievement(
                forPostReference: postReference,
                detailCache: detailCache,
                sharedAchievements: sharedAchievements
            ), resolved.id == achievementID {
                keys.insert(SharedContentReference.achievementPost(postReference).stableKey)
            }
        }
        return keys
    }

    private static func primaryShareUnavailable(
        _ message: Message,
        unavailableKeys: Set<String>,
        sharedPosts: [PostID: Post]
    ) -> Bool {
        guard SharedContentMessageSupport.isInternallySharedContent(message) else { return false }

        if let reference = message.sharedContent {
            if unavailableKeys.contains(reference.stableKey) {
                return true
            }
            if case .feedPost(let postID) = reference,
               unavailableKeys.contains(SharedContentReference.profilePost(postID).stableKey)
                || unavailableKeys.contains(SharedContentReference.achievementPost(postID).stableKey)
            {
                return true
            }
            if case .profilePost(let postID) = reference,
               unavailableKeys.contains(SharedContentReference.feedPost(postID).stableKey)
            {
                return true
            }
        }

        let isDedicatedTradeShare =
            message.kind == .tradeShare
            || (message.sharedContent == nil && message.attachments.contains { $0.tradeID != nil })

        guard isDedicatedTradeShare else { return false }

        return SharedContentMessageSupport.referencedTradeIDs(for: message, sharedPosts: sharedPosts)
            .contains { tradeID in
                unavailableKeys.contains(SharedContentReference.trade(tradeID).stableKey)
            }
    }

    private static func shouldRemoveEntireMessage(_ message: Message) -> Bool {
        if SharedContentMessageSupport.userWrittenMessage(for: message) != nil {
            return false
        }
        if message.kind == .voice {
            return false
        }
        if message.attachments.contains(where: { attachment in
            attachment.tradeID == nil
                && (attachment.media.kind == .image || attachment.media.kind == .audio)
        }) {
            return false
        }
        if message.kind == .text,
           let body = SharedContentMessageSupport.normalizedUserWrittenBody(message.body)
        {
            return body.isEmpty
        }
        return true
    }

    private static func stripStructuredShare(from message: Message) -> Message? {
        var updated = message
        updated.sharedContent = nil
        updated.attachments = updated.attachments.filter { $0.tradeID == nil }

        switch updated.kind {
        case .tradeShare, .feedPostShare, .profilePostShare, .achievementPostShare, .reelShare, .profileShare:
            if updated.kind == .voice || updated.attachments.contains(where: { $0.media.kind == .audio }) {
                updated.kind = .voice
            } else if updated.attachments.contains(where: { $0.media.kind == .image }) {
                updated.kind = .media
            } else {
                updated.kind = .text
            }
        default:
            break
        }

        if let caption = SharedContentMessageSupport.userWrittenMessage(for: message) {
            updated.body = caption
            return updated
        }

        if updated.kind == .media || updated.kind == .voice {
            updated.body = nil
            return updated
        }

        if let body = SharedContentMessageSupport.normalizedUserWrittenBody(updated.body) {
            updated.body = body
            return updated
        }

        return nil
    }
}