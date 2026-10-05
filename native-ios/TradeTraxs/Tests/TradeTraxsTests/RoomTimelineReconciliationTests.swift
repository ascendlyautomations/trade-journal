import XCTest
@testable import TradeTraxs

final class RoomTimelineReconciliationTests: XCTestCase {
    func testReconcileServerFirstPagePreservesOlderDiskMessages() {
        let viewer = ProfileID("viewer-1")
        let oldA = makeMessage(id: "a", body: "text A", at: 100)
        let oldTrade = makeMessage(id: "c", kind: .tradeShare, body: nil, at: 300, tradeID: TradeID("trade-c"))
        let disk = [oldA, makeMessage(id: "b", body: "text B", at: 200), oldTrade]

        let bootstrapRecent = [
            makeMessage(id: "b", body: "text B updated", at: 200),
            makeMessage(id: "d", body: "text D", at: 400),
        ]

        let reconciled = ConversationMessageMerge.reconcileServerFirstPage(
            existing: disk,
            incoming: bootstrapRecent,
            dropOmittedInWindow: false
        )

        XCTAssertEqual(reconciled.map(\.id), [oldA.id, MessageID("b"), oldTrade.id, MessageID("d")])
        XCTAssertEqual(reconciled.first(where: { $0.id == MessageID("b") })?.body, "text B updated")
    }

    func testGuestBootstrapDTOMapsTextWithoutRoomIDColumn() {
        var dto = RoomDTO.Message()
        dto.id = "msg-text"
        dto.sender_id = "sender-1"
        dto.type = "text"
        dto.body = "hello history"
        dto.section_id = "section-1"
        dto.created_at = "2026-01-01T00:00:00Z"

        let roomMessage = RoomMessageDTOMapper.mapMessage(dto, fallbackRoomID: RoomID("room-1"))
        XCTAssertNotNil(roomMessage)
        let display = roomMessage.map(RoomMessageMapping.displayMessage(from:))
        XCTAssertEqual(display?.kind, .text)
        XCTAssertEqual(display?.body, "hello history")
    }

    func testBootstrapMergeKeepsHistoryWhenNewOptimisticTradeArrives() {
        let viewer = ProfileID("viewer-1")
        let history = [
            makeMessage(id: "text-1", body: "hello", at: 100),
            makeMessage(id: "trade-old", kind: .tradeShare, body: nil, at: 200, tradeID: TradeID("t-old")),
        ]
        let optimisticTrade = Message(
            id: MessageID("temp-share"),
            conversationID: ConversationID("channel-1"),
            senderProfileID: viewer,
            kind: .tradeShare,
            body: nil,
            attachments: [
                MessageAttachment(
                    id: "t-new",
                    media: MediaReference(id: "t-new", kind: .file, altText: nil),
                    tradeID: TradeID("t-new")
                ),
            ],
            replyToMessageID: nil,
            createdAt: Date(timeIntervalSince1970: 300),
            isReadByViewer: true
        )
        let merged = ConversationMessageMerge.mergeMessages(
            existing: history,
            incoming: [optimisticTrade],
            viewerID: viewer
        )
        XCTAssertEqual(merged.map(\.id.rawValue), ["text-1", "trade-old", "temp-share"])
    }

    func testBootstrapDTOMapperPreservesMixedHistory() {
        let roomID = RoomID("room-1")
        var text = RoomDTO.Message()
        text.id = "t1"
        text.sender_id = "u1"
        text.type = "text"
        text.body = "hi"
        text.room_id = roomID.rawValue
        text.created_at = "2026-01-01T00:00:00Z"

        var image = RoomDTO.Message()
        image.id = "i1"
        image.sender_id = "u1"
        image.type = "media"
        image.image_url = "https://example.com/a.jpg"
        image.room_id = roomID.rawValue
        image.created_at = "2026-01-01T00:01:00Z"

        var tradeJSON = RoomDTO.Message()
        tradeJSON.id = "tr1"
        tradeJSON.sender_id = "u1"
        tradeJSON.type = "trade"
        tradeJSON.body = #"{"share_type":"trade","trade_id":"trade-1"}"#
        tradeJSON.room_id = roomID.rawValue
        tradeJSON.created_at = "2026-01-01T00:02:00Z"

        let mapped = [text, image, tradeJSON].compactMap { RoomMessageDTOMapper.mapMessage($0) }
        XCTAssertEqual(mapped.count, 3)
        let display = mapped.map(RoomMessageMapping.displayMessage(from:))
        XCTAssertEqual(display.map(\.kind), [.text, .media, .tradeShare])
    }

    private func makeMessage(
        id: String,
        kind: MessageKind = .text,
        body: String?,
        at: TimeInterval,
        tradeID: TradeID? = nil
    ) -> Message {
        Message(
            id: MessageID(id),
            conversationID: ConversationID("channel-1"),
            senderProfileID: ProfileID("sender-1"),
            kind: kind,
            body: body,
            attachments: tradeID.map {
                [
                    MessageAttachment(
                        id: $0.rawValue,
                        media: MediaReference(id: $0.rawValue, kind: .file, altText: nil),
                        tradeID: $0
                    ),
                ]
            } ?? [],
            replyToMessageID: nil,
            createdAt: Date(timeIntervalSince1970: at),
            isReadByViewer: true
        )
    }
}
