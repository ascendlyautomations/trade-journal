import Foundation

/// Maps `MessagesBootstrapV1` RPC rows into ``MessagesInboxStore`` presentation state.
@MainActor
enum MessagingBootstrapApplier {
    static func apply(
        _ bootstrap: MessagesBootstrapV1,
        inboxStore: MessagesInboxStore,
        detailCache: DetailPresentationCache
    ) throws {
        try bootstrap.validateContractVersion()

        let viewerID = bootstrap.meta.viewer_id ?? ""
        let mutedIDs = Set(bootstrap.data.muted_ids)

        for (_, card) in bootstrap.data.peers {
            seedAuthorCard(card, detailCache: detailCache)
        }

        for row in bootstrap.data.conversations {
            for participant in row.participants where participant.user_id != viewerID {
                seedParticipant(participant, detailCache: detailCache)
            }
        }

        let mapped = bootstrap.data.conversations.compactMap {
            mapConversation($0, viewerID: viewerID, mutedIDs: mutedIDs)
        }
        inboxStore.mergeConversationsFromBootstrap(mapped)
    }

    private static func mapConversation(
        _ row: MessagingConversationV1,
        viewerID: String,
        mutedIDs: Set<String>
    ) -> Conversation? {
        let trimmedID = row.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return nil }

        let participantIDs = row.participants.map { ProfileID($0.user_id) }
        let isGroup = row.is_group
        let other = row.participants.first { $0.user_id != viewerID }
        let peerUsername = isGroup ? nil : (trimmedNil(other?.username) ?? "user")
        let title: String?
        if isGroup {
            title = trimmedNil(row.name) ?? "Group Chat"
        } else {
            title = trimmedNil(other?.display_name)
                ?? trimmedNil(other?.username)
                ?? peerUsername
        }
        let avatarURL = isGroup ? row.avatar_url : other?.avatar_url
        let lastAt = row.last_message_at.flatMap { ISO8601.date(from: $0) }
        let lastMessageID = row.last_message_id.flatMap { raw -> MessageID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : MessageID(trimmed)
        }

        return Conversation(
            id: ConversationID(trimmedID),
            participantProfileIDs: participantIDs,
            title: title,
            peerUsername: peerUsername,
            avatar: trimmedNil(avatarURL).flatMap {
                MediaReference(id: $0, kind: .image, altText: nil)
            },
            isGroup: isGroup,
            isPinned: row.is_pinned,
            lastMessagePreview: row.last_message,
            lastMessageAt: lastAt,
            lastMessageID: lastMessageID,
            unreadCount: row.unread_count,
            isMuted: row.muted || mutedIDs.contains(trimmedID),
            updatedAt: lastAt ?? .distantPast
        )
    }

    private static func seedAuthorCard(_ card: AuthorCardV1, detailCache: DetailPresentationCache) {
        let profileID = ProfileID(card.id)
        let username = trimmedNil(card.username) ?? "user"
        let display = trimmedNil(card.display_name)
        detailCache.seed(
            Profile(
                id: profileID,
                userID: UserID(card.id),
                username: username,
                displayName: display ?? username,
                bio: nil,
                avatar: trimmedNil(card.avatar_url).flatMap {
                    MediaReference(id: $0, kind: .image, altText: nil)
                },
                traderType: .futures,
                tradingStyle: nil,
                primaryMarket: nil,
                startedTradingAt: nil,
                isPrivate: false,
                isCreator: false,
                createdAt: .now
            )
        )
    }

    private static func seedParticipant(
        _ participant: MessagingParticipantV1,
        detailCache: DetailPresentationCache
    ) {
        let profileID = ProfileID(participant.user_id)
        let username = trimmedNil(participant.username) ?? "user"
        let display = trimmedNil(participant.display_name)
        detailCache.seed(
            Profile(
                id: profileID,
                userID: UserID(participant.user_id),
                username: username,
                displayName: display ?? username,
                bio: nil,
                avatar: trimmedNil(participant.avatar_url).flatMap {
                    MediaReference(id: $0, kind: .image, altText: nil)
                },
                traderType: .futures,
                tradingStyle: nil,
                primaryMarket: nil,
                startedTradingAt: nil,
                isPrivate: false,
                isCreator: false,
                createdAt: .now
            )
        )
    }

    private static func trimmedNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
