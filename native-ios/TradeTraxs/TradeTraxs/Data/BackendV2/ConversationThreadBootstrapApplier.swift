import Foundation

/// Maps `ConversationThreadBootstrapV1` into native conversation + message domain models.
nonisolated enum ConversationThreadBootstrapApplier {
    struct Applied: Sendable {
        var conversation: Conversation
        var messages: [Message]
        var nextCursor: String?
        var hasMoreMessages: Bool
        var markReadApplied: Bool
        var notificationsMarkedRead: Int
        var skippedMessages: Int
    }

    @MainActor
    static func apply(
        _ bootstrap: ConversationThreadBootstrapV1,
        conversationID: ConversationID,
        viewerID: ProfileID,
        detailCache: DetailPresentationCache
    ) throws -> Applied {
        try bootstrap.validateContractVersion()
        try bootstrap.validateRequiredFields()

        let convoWire = bootstrap.data.conversation
        let participantIDs = bootstrap.data.participants.map { ProfileID($0.user_id) }

        for participant in bootstrap.data.participants {
            guard let profileWire = participant.profiles else { continue }
            let profileID = ProfileID(profileWire.id ?? participant.user_id)
            let profile = Profile(
                id: profileID,
                userID: UserID(profileID.rawValue),
                username: profileWire.username ?? "user",
                displayName: profileWire.username ?? "User",
                bio: nil,
                avatar: profileWire.avatar_url.flatMap {
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
            detailCache.seed(profile)
        }

        let peerUsername = bootstrap.data.participants.first(where: { ProfileID($0.user_id) != viewerID })?
            .profiles?.username

        var messages: [Message] = []
        var skipped = 0
        messages.reserveCapacity(bootstrap.data.messages.count)
        for row in bootstrap.data.messages {
            do {
                messages.append(try mapMessage(row, viewerID: viewerID, conversationID: conversationID))
            } catch {
                skipped += 1
            }
        }

        if bootstrap.data.messages.isEmpty == false, messages.isEmpty, skipped > 0 {
            throw ConversationThreadContractError.malformedMessage("all message rows failed mapping")
        }

        messages = MessageChronology.sortAscending(messages)
        let latestMessage = MessageChronology.newest(in: messages)
        let conversation = Conversation(
            id: ConversationID(convoWire.id),
            participantProfileIDs: participantIDs,
            title: convoWire.name,
            peerUsername: peerUsername,
            avatar: convoWire.avatar_url.flatMap {
                MediaReference(id: $0, kind: .image, altText: nil)
            },
            isGroup: convoWire.is_group.value ?? false,
            isPinned: convoWire.is_pinned.value ?? false,
            lastMessagePreview: latestMessage.map { ConversationInboxActivity.preview(for: $0) },
            lastMessageAt: latestMessage?.createdAt,
            lastMessageID: latestMessage?.id,
            unreadCount: Int(bootstrap.data.unread_count.value ?? 0),
            isMuted: bootstrap.data.notifications_enabled.value == false,
            updatedAt: latestMessage?.createdAt ?? .distantPast
        )

        return Applied(
            conversation: conversation,
            messages: messages,
            nextCursor: bootstrap.data.next_message_cursor,
            hasMoreMessages: bootstrap.data.has_more_messages.value ?? false,
            markReadApplied: bootstrap.data.mark_read.applied.value ?? false,
            notificationsMarkedRead: Int(bootstrap.data.notifications_marked_read.value ?? 0),
            skippedMessages: skipped
        )
    }

    private static func mapMessage(
        _ row: ConversationThreadMessageV1,
        viewerID: ProfileID,
        conversationID: ConversationID
    ) throws -> Message {
        let trimmedID = row.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw ConversationThreadContractError.malformedMessage("message.id")
        }
        guard let createdRaw = row.created_at,
              let createdAt = ISO8601.date(from: createdRaw)
        else {
            throw ConversationThreadContractError.malformedMessage("message.created_at")
        }

        let senderRaw = row.sender_id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !senderRaw.isEmpty else {
            throw ConversationThreadContractError.malformedMessage("message.sender_id")
        }
        let sender = ProfileID(senderRaw)

        let tradeID = row.trade_id.flatMap { raw -> TradeID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : TradeID(trimmed)
        }
        let isTrade = (row.type?.lowercased() == "trade") || tradeID != nil
        let imageURL = row.image_url?.trimmingCharacters(in: .whitespacesAndNewlines)

        let attachments: [MessageAttachment] = {
            if let tradeID {
                return [
                    MessageAttachment(
                        id: tradeID.rawValue,
                        media: MediaReference(id: tradeID.rawValue, kind: .file, altText: "Shared trade"),
                        tradeID: tradeID
                    ),
                ]
            }
            guard let imageURL, !imageURL.isEmpty else { return [] }
            return [
                MessageAttachment(
                    id: imageURL,
                    media: MediaReference(id: imageURL, kind: .image, altText: nil),
                    tradeID: nil
                ),
            ]
        }()

        let kind: MessageKind = {
            if row.is_system.value == true { return .system }
            if isTrade { return .tradeShare }
            if let raw = row.type?.lowercased(), raw == "system" { return .system }
            return attachments.isEmpty ? .text : .media
        }()

        let replyID = row.parent_message_id.flatMap { raw -> MessageID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : MessageID(trimmed)
        }

        let isRead = row.seen_by.contains(viewerID.rawValue)

        return Message(
            id: MessageID(trimmedID),
            conversationID: conversationID,
            senderProfileID: sender,
            kind: kind,
            body: isTrade ? nil : row.content,
            attachments: attachments,
            replyToMessageID: replyID,
            createdAt: createdAt,
            isReadByViewer: isRead
        )
    }
}
