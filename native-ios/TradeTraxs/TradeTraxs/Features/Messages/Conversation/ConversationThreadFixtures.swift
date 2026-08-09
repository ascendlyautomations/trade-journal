import Foundation

enum ConversationThreadFixtures {
    static func messages(
        conversationID: ConversationID,
        viewerID: ProfileID,
        peerID: ProfileID
    ) -> [Message] {
        let now = Date()
        return [
            Message(
                id: MessageID("\(conversationID.rawValue)-1"),
                conversationID: conversationID,
                senderProfileID: peerID,
                kind: .text,
                body: "Did you catch that NQ sweep?",
                attachments: [],
                replyToMessageID: nil,
                createdAt: now.addingTimeInterval(-3_600),
                isReadByViewer: true
            ),
            Message(
                id: MessageID("\(conversationID.rawValue)-2"),
                conversationID: conversationID,
                senderProfileID: viewerID,
                kind: .text,
                body: "Yes — clean displacement off the FVG.",
                attachments: [],
                replyToMessageID: nil,
                createdAt: now.addingTimeInterval(-3_400),
                isReadByViewer: true
            ),
            Message(
                id: MessageID("\(conversationID.rawValue)-3"),
                conversationID: conversationID,
                senderProfileID: peerID,
                kind: .text,
                body: "Sharing my London open checklist next.",
                attachments: [],
                replyToMessageID: nil,
                createdAt: now.addingTimeInterval(-120),
                isReadByViewer: false
            ),
        ]
    }
}
