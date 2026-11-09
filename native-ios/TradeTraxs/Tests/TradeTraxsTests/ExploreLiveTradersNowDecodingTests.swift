import XCTest
@testable import TradeTraxs

final class ExploreLiveTradersNowDecodingTests: XCTestCase {
    private func makeDecoder() -> JSONDecoder {
        let json = JSONDecoder()
        json.keyDecodingStrategy = .useDefaultKeys
        return json
    }

    private func decodeEnvelope(_ json: String) throws -> ExploreLiveTradersNowEnvelope {
        let data = Data(json.utf8)
        return try makeDecoder().decode(ExploreLiveTradersNowEnvelope.self, from: data)
    }

    func testDecodesEmptyItemsWithoutError() throws {
        let envelope = try decodeEnvelope(#"{"items":[]}"#)
        XCTAssertEqual(envelope.items?.count, 0)
        XCTAssertEqual((envelope.items ?? []).map { $0.toDomain() }, [])
    }

    func testDecodesRepresentativeBFFRow() throws {
        let envelope = try decodeEnvelope(
            """
            {"items":[{"broadcastSessionId":"sess-1","roomId":"room-uuid","roomSlug":null,"roomName":"Alpha Room","broadcasterUserId":"user-uuid","broadcasterDisplayName":"Alex","broadcasterUsername":"alex","broadcasterAvatarUrl":null,"viewerCount":2,"startedAt":"2026-11-07T19:00:00.000Z","videoSource":"camera"}]}
            """
        )
        let row = try XCTUnwrap(envelope.items?.first)
        let domain = row.toDomain()
        XCTAssertEqual(domain.broadcastSessionId, "sess-1")
        XCTAssertEqual(domain.roomID, RoomID("room-uuid"))
        XCTAssertEqual(domain.broadcasterProfileID, ProfileID("user-uuid"))
        XCTAssertEqual(domain.roomName, "Alpha Room")
        XCTAssertEqual(domain.viewerCount, 2)
        XCTAssertEqual(domain.videoSource, "camera")
    }

    func testDecodesViewerCountWhenEncodedAsDouble() throws {
        let envelope = try decodeEnvelope(
            #"{"items":[{"broadcastSessionId":"s","roomId":"r","roomSlug":null,"roomName":"R","broadcasterUserId":"u","broadcasterDisplayName":null,"broadcasterUsername":null,"broadcasterAvatarUrl":null,"viewerCount":3.0,"startedAt":"2026-11-07T00:00:00Z","videoSource":"obs"}]}"#
        )
        let domain = try XCTUnwrap(envelope.items?.first?.toDomain())
        XCTAssertEqual(domain.viewerCount, 3)
        XCTAssertEqual(domain.videoSource, "obs")
    }
}
