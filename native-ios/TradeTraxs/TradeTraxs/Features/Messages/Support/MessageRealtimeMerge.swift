import Foundation

nonisolated enum MessageRealtimeMerge {
    static func dmMessage(
        from recordPayload: Data,
        conversationID: ConversationID,
        viewerID: ProfileID?
    ) -> Message? {
        guard let dto = PostgresChangeRecordCodec.decode(MessageDTO.Message.self, from: recordPayload)
        else { return nil }
        if dto.deleted_for_everyone == true { return nil }
        guard let mapped = try? MessageMapper.mapToDomain(dto) else { return nil }
        if mapped.conversationID != conversationID { return mapped }
        return mapped
    }

    static func roomDisplayMessage(from recordPayload: Data) -> Message? {
        guard let dto = PostgresChangeRecordCodec.decode(RoomDTO.Message.self, from: recordPayload),
              let id = dto.id,
              let roomID = dto.room_id,
              let sender = dto.sender_id ?? dto.sender_profile_id ?? dto.user_id
        else { return nil }
        let body = dto.body ?? dto.content
        let roomMessage = RoomMessage(
            id: RoomMessageID(id),
            roomID: RoomID(roomID),
            senderProfileID: ProfileID(sender),
            body: body,
            attachedTradeID: dto.trade_id.flatMap { TradeID($0) },
            media: [],
            parentMessageID: dto.parent_message_id.map { RoomMessageID($0) },
            channelID: dto.section_id.map { RoomChannelID($0) },
            isPinned: dto.is_pinned ?? false,
            createdAt: ISO8601.date(from: dto.created_at) ?? Date(),
            shareType: dto.type,
            reactions: []
        )
        return RoomMessageMapping.displayMessage(from: roomMessage)
    }
}
