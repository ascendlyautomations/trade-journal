import Foundation

/// Maps `RoomMessage` ↔ display `Message` so Trade Rooms reuse DM bubble UI.
enum RoomMessageMapping {
    static func displayMessage(from roomMessage: RoomMessage) -> Message {
        // ConversationID is the selected channel (subroom), not the Trade Room container.
        let conversationID = ConversationID(
            roomMessage.channelID?.rawValue ?? roomMessage.roomID.rawValue
        )
        if let tradeID = roomMessage.attachedTradeID {
            return Message(
                id: MessageID(roomMessage.id.rawValue),
                conversationID: conversationID,
                senderProfileID: roomMessage.senderProfileID,
                kind: .tradeShare,
                body: nil,
                attachments: [
                    MessageAttachment(
                        id: tradeID.rawValue,
                        media: MediaReference(id: tradeID.rawValue, kind: .file, altText: "Shared trade"),
                        tradeID: tradeID
                    ),
                ],
                replyToMessageID: roomMessage.parentMessageID.map { MessageID($0.rawValue) },
                createdAt: roomMessage.createdAt,
                isReadByViewer: true
            )
        }

        var attachments: [MessageAttachment] = roomMessage.media.enumerated().map { index, media in
            MessageAttachment(
                id: media.id.isEmpty ? "\(roomMessage.id.rawValue)-\(index)" : media.id,
                media: media,
                tradeID: nil
            )
        }
        let body = roomMessage.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if attachments.isEmpty, looksLikeImageURL(body) {
            attachments = [
                MessageAttachment(
                    id: body,
                    media: MediaReference(id: body, kind: .image, altText: nil),
                    tradeID: nil
                ),
            ]
        }
        return Message(
            id: MessageID(roomMessage.id.rawValue),
            conversationID: conversationID,
            senderProfileID: roomMessage.senderProfileID,
            kind: attachments.isEmpty ? .text : .media,
            body: attachments.isEmpty ? roomMessage.body : (body.isEmpty || looksLikeImageURL(body) ? nil : body),
            attachments: attachments,
            replyToMessageID: roomMessage.parentMessageID.map { MessageID($0.rawValue) },
            createdAt: roomMessage.createdAt,
            isReadByViewer: true
        )
    }

    static func roomMessage(
        from display: Message,
        roomID: RoomID,
        channelID: RoomChannelID? = nil,
        isPinned: Bool = false
    ) -> RoomMessage {
        RoomMessage(
            id: RoomMessageID(display.id.rawValue),
            roomID: roomID,
            senderProfileID: display.senderProfileID,
            body: display.body,
            attachedTradeID: display.attachments.first?.tradeID,
            media: display.attachments.map(\.media),
            parentMessageID: display.replyToMessageID.map { RoomMessageID($0.rawValue) },
            channelID: channelID ?? RoomChannelID(display.conversationID.rawValue),
            isPinned: isPinned,
            createdAt: display.createdAt
        )
    }

    static func looksLikeImageURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        guard scheme == "http" || scheme == "https" else { return false }
        let path = url.path.lowercased()
        return path.hasSuffix(".jpg")
            || path.hasSuffix(".jpeg")
            || path.hasSuffix(".png")
            || path.hasSuffix(".webp")
            || path.hasSuffix(".gif")
            || path.contains("/storage/v1/object/public/")
    }
}
