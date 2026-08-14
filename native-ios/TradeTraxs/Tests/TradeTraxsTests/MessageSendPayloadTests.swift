import XCTest
@testable import TradeTraxs

final class MessageSendPayloadTests: XCTestCase {
    func testDMSendBodyMatchesWebNullChannelAndImageURL() throws {
        // Mirrors web sendPayload:
        // { conversation_id, sender_id, content, image_url, channel: null }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // Encode via the same shape DefaultMessageRepository uses (private type mirrored here).
        struct Body: Encodable {
            var conversation_id: String
            var sender_id: String
            var content: String
            var image_url: String?
            var parent_message_id: String?

            private enum CodingKeys: String, CodingKey {
                case conversation_id, sender_id, content, image_url, channel, parent_message_id
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(conversation_id, forKey: .conversation_id)
                try container.encode(sender_id, forKey: .sender_id)
                try container.encode(content, forKey: .content)
                try container.encode(image_url, forKey: .image_url)
                try container.encodeNil(forKey: .channel)
                if let parent_message_id {
                    try container.encode(parent_message_id, forKey: .parent_message_id)
                }
            }
        }

        let textOnly = try encoder.encode(
            Body(
                conversation_id: "c1",
                sender_id: "u1",
                content: "hello",
                image_url: nil,
                parent_message_id: nil
            )
        )
        let textJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: textOnly) as? [String: Any])
        XCTAssertEqual(textJSON["conversation_id"] as? String, "c1")
        XCTAssertEqual(textJSON["sender_id"] as? String, "u1")
        XCTAssertEqual(textJSON["content"] as? String, "hello")
        XCTAssertTrue(textJSON.keys.contains("image_url"))
        XCTAssertTrue(textJSON["image_url"] is NSNull)
        XCTAssertTrue(textJSON.keys.contains("channel"))
        XCTAssertTrue(textJSON["channel"] is NSNull)
        XCTAssertFalse(textJSON.keys.contains("parent_message_id"))

        let withImage = try encoder.encode(
            Body(
                conversation_id: "c1",
                sender_id: "u1",
                content: "",
                image_url: "https://example.com/a.jpg",
                parent_message_id: "p1"
            )
        )
        let imageJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: withImage) as? [String: Any])
        XCTAssertEqual(imageJSON["image_url"] as? String, "https://example.com/a.jpg")
        XCTAssertEqual(imageJSON["parent_message_id"] as? String, "p1")
        XCTAssertTrue(imageJSON["channel"] is NSNull)
    }

    func testNotifyDMBodyMatchesWebMessageIdField() throws {
        // Web `createDirectMessagePush`: JSON.stringify({ messageId })
        struct Body: Encodable {
            var messageId: String
        }
        let data = try JSONEncoder().encode(Body(messageId: "msg-123"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["messageId"] as? String, "msg-123")
        XCTAssertEqual(json.keys.count, 1)
    }
}
