import Foundation

/// Single decode path for room message rows — REST, bootstrap RPC, and guest bootstrap must match.
nonisolated enum RoomMessageDTOMapper {
    static func mapMessage(_ dto: RoomDTO.Message, fallbackRoomID: RoomID? = nil) -> RoomMessage? {
        guard let id = dto.id else { return nil }
        let roomIDRaw = dto.room_id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRoomID: RoomID? = {
            if let roomIDRaw, !roomIDRaw.isEmpty { return RoomID(roomIDRaw) }
            return fallbackRoomID
        }()
        guard let roomID = resolvedRoomID else { return nil }
        let sender = dto.sender_id ?? dto.sender_profile_id ?? dto.user_id
        guard let sender else { return nil }
        let tradeID = dto.trade_id.flatMap { raw -> TradeID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : TradeID(trimmed)
        }
        let rawContent = dto.body ?? dto.content ?? ""
        if dto.type?.lowercased() == StoryShareMessageSupport.messageType
            || StoryShareMessageSupport.isStoryShare(type: dto.type, content: rawContent)
        {
            return RoomMessage(
                id: RoomMessageID(id),
                roomID: roomID,
                senderProfileID: ProfileID(sender),
                body: rawContent,
                attachedTradeID: nil,
                media: [],
                parentMessageID: dto.parent_message_id.map { RoomMessageID($0) },
                channelID: dto.section_id.map { RoomChannelID($0) },
                isPinned: dto.is_pinned ?? false,
                createdAt: ISO8601.date(from: dto.created_at) ?? Date(),
                reactions: (dto.room_message_reactions ?? []).compactMap {
                    mapReaction($0, fallbackMessageID: RoomMessageID(id))
                }
            )
        }
        if SharedContentRoomMessageSupport.isStructuredShare(type: dto.type, content: rawContent) {
            let structuredTradeID = SharedContentRoomMessageSupport.decode(from: rawContent).flatMap { reference -> TradeID? in
                if case .trade(let id) = reference { return id }
                return nil
            }
            return RoomMessage(
                id: RoomMessageID(id),
                roomID: roomID,
                senderProfileID: ProfileID(sender),
                body: rawContent,
                attachedTradeID: tradeID ?? structuredTradeID,
                media: [],
                parentMessageID: dto.parent_message_id.map { RoomMessageID($0) },
                channelID: dto.section_id.map { RoomChannelID($0) },
                isPinned: dto.is_pinned ?? false,
                createdAt: ISO8601.date(from: dto.created_at) ?? Date(),
                shareType: dto.type,
                reactions: (dto.room_message_reactions ?? []).compactMap {
                    mapReaction($0, fallbackMessageID: RoomMessageID(id))
                }
            )
        }
        let imageURL = dto.image_url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let audioURL = dto.audio_url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceDuration = dto.audio_duration_ms.map { Double($0) / 1_000.0 }
        let isVoice = dto.type?.lowercased() == "voice" || !(audioURL?.isEmpty ?? true)
        let media: [MediaReference] = {
            if let audioURL, !audioURL.isEmpty {
                return [MediaReference(id: audioURL, kind: .audio, altText: voiceDuration.map { String($0) })]
            }
            guard let imageURL, !imageURL.isEmpty else { return [] }
            return [MediaReference(id: imageURL, kind: .image, altText: nil)]
        }()
        return RoomMessage(
            id: RoomMessageID(id),
            roomID: roomID,
            senderProfileID: ProfileID(sender),
            body: isVoice ? nil : (dto.body ?? dto.content),
            attachedTradeID: tradeID,
            media: media,
            parentMessageID: dto.parent_message_id.map { RoomMessageID($0) },
            channelID: dto.section_id.map { RoomChannelID($0) },
            isPinned: dto.is_pinned ?? false,
            createdAt: ISO8601.date(from: dto.created_at) ?? Date(),
            reactions: (dto.room_message_reactions ?? []).compactMap {
                mapReaction($0, fallbackMessageID: RoomMessageID(id))
            }
        )
    }

    static func mapReaction(
        _ dto: RoomDTO.ReactionRow,
        fallbackMessageID: RoomMessageID
    ) -> RoomMessageReaction? {
        guard let id = dto.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
              let reaction = dto.reaction?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reaction.isEmpty,
              RoomMessageReactionSemantics.supportedEmojis.contains(reaction)
        else { return nil }
        let messageRaw = dto.message_id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageID = messageRaw.flatMap { raw -> RoomMessageID? in
            raw.isEmpty ? nil : RoomMessageID(raw)
        } ?? fallbackMessageID
        guard let userRaw = dto.user_id?.trimmingCharacters(in: .whitespacesAndNewlines), !userRaw.isEmpty
        else { return nil }
        return RoomMessageReaction(
            id: id,
            messageID: messageID,
            userID: ProfileID(userRaw),
            reaction: reaction,
            createdAt: ISO8601.date(from: dto.created_at)
        )
    }
}
