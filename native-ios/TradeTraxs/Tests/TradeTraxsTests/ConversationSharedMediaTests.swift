import XCTest
@testable import TradeTraxs

final class ConversationSharedMediaTests: XCTestCase {
    func testPaginationMergeDeduplicatesByMessageID() {
        let first = ConversationSharedMediaItem(
            id: MessageID("m1"),
            senderID: nil,
            imageURL: "https://example.com/1.jpg",
            createdAt: "2026-01-02T00:00:00Z"
        )
        let second = ConversationSharedMediaItem(
            id: MessageID("m2"),
            senderID: nil,
            imageURL: "https://example.com/2.jpg",
            createdAt: "2026-01-01T00:00:00Z"
        )
        let duplicate = ConversationSharedMediaItem(
            id: MessageID("m2"),
            senderID: nil,
            imageURL: "https://example.com/2b.jpg",
            createdAt: "2026-01-01T00:00:00Z"
        )
        let merged = ConversationSharedMediaPagination.merged(
            existing: [first],
            page: [second, duplicate]
        )
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.id), [MessageID("m1"), MessageID("m2")])
    }

    func testFetcherDecodesRowsAndBuildsCursorPage() async {
        let json = """
        [
          {
            "message_id": "aaa-bbb",
            "sender_id": "user-1",
            "image_url": "https://cdn.example.com/a.jpg",
            "created_at": "2026-03-01T12:00:00Z"
          },
          {
            "message_id": "",
            "sender_id": null,
            "image_url": "skip",
            "created_at": "2026-03-01T11:00:00Z"
          }
        ]
        """
        let rpc = SharedMediaTestRPCClient(json: json)
        let conversationID = ConversationID("conv-1")
        let result = await ConversationSharedMediaFetcher.fetch(
            conversationID: conversationID,
            cursor: nil,
            rpc: rpc
        )
        guard case .success(let items) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id.rawValue, "aaa-bbb")
        XCTAssertEqual(items[0].senderID?.rawValue, "user-1")
        XCTAssertEqual(
            rpc.lastFunctionName,
            "get_conversation_shared_media"
        )
        let cursor = ConversationSharedMediaPagination.nextCursor(from: items)
        XCTAssertEqual(cursor?.id.rawValue, "aaa-bbb")
        XCTAssertEqual(cursor?.createdAt, "2026-03-01T12:00:00Z")

        let page2JSON = """
        [
          {
            "message_id": "older",
            "sender_id": null,
            "image_url": "https://cdn.example.com/old.jpg",
            "created_at": "2026-02-01T12:00:00Z"
          }
        ]
        """
        rpc.json = page2JSON
        let page2 = await ConversationSharedMediaFetcher.fetch(
            conversationID: conversationID,
            cursor: cursor,
            rpc: rpc
        )
        guard case .success(let older) = page2 else {
            return XCTFail("Expected page 2")
        }
        XCTAssertEqual(older.count, 1)
        XCTAssertNotNil(rpc.lastBody)
        XCTAssertTrue(rpc.lastBody?.contains("p_before_id") == true)
    }

    @MainActor
    func testThumbnailFailureKeepsItemsInGallery() async {
        let conversationID = ConversationID("conv-thumbs")
        let rpc = SharedMediaTestRPCClient(json: """
        [{"message_id":"m1","sender_id":null,"image_url":"https://example.com/1.jpg","created_at":"2026-03-01T00:00:00Z"}]
        """)
        let vm = ConversationSharedMediaViewModel(conversationID: conversationID, rpc: rpc)
        await vm.open()
        XCTAssertEqual(vm.visibleItems.count, 1)
        vm.markThumbnailFailed(vm.visibleItems[0])
        XCTAssertEqual(vm.visibleItems.count, 1)
        XCTAssertTrue(vm.isThumbnailFailed(vm.visibleItems[0]))
    }

    @MainActor
    func testBackgroundRefreshDoesNotWipeLoadedItemsWhenRPCReturnsEmpty() async {
        let conversationID = ConversationID("conv-stale")
        let rpc = StaleRefreshSharedMediaRPCClient()
        let vm = ConversationSharedMediaViewModel(conversationID: conversationID, rpc: rpc)
        await vm.open()
        XCTAssertEqual(vm.visibleItems.count, 2)
        await vm.open()
        XCTAssertEqual(vm.visibleItems.count, 2)
        XCTAssertEqual(vm.openCount, 2)
    }

    @MainActor
    func testViewModelAppendsNextPage() async {
        let conversationID = ConversationID("conv-gallery")
        let rpc = PaginatedSharedMediaRPCClient()
        let vm = ConversationSharedMediaViewModel(conversationID: conversationID, rpc: rpc)
        await vm.open()
        XCTAssertEqual(vm.visibleItems.count, 12)
        XCTAssertTrue(vm.hasMore)
        await vm.loadMoreIfNeeded()
        XCTAssertEqual(vm.visibleItems.count, 13)
        XCTAssertFalse(vm.hasMore)
    }
}

private final class SharedMediaTestRPCClient: RPCClient, @unchecked Sendable {
    var json: String
    private(set) var lastFunctionName: String?
    private(set) var lastBody: String?

    init(json: String) { self.json = json }

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        try await call(functionName: functionName, jsonBody: Data())
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        lastFunctionName = functionName
        lastBody = String(data: jsonBody, encoding: .utf8)
        return Data(json.utf8)
    }
}

private final class StaleRefreshSharedMediaRPCClient: RPCClient, @unchecked Sendable {
    private var callIndex = 0

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        try await call(functionName: functionName, jsonBody: Data())
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        callIndex += 1
        if callIndex == 1 {
            return Data(
                """
                [
                  {"message_id":"a","sender_id":null,"image_url":"https://example.com/a.jpg","created_at":"2026-03-02T00:00:00Z"},
                  {"message_id":"b","sender_id":null,"image_url":"https://example.com/b.jpg","created_at":"2026-03-01T00:00:00Z"}
                ]
                """.utf8
            )
        }
        return Data("[]".utf8)
    }
}

private final class PaginatedSharedMediaRPCClient: RPCClient, @unchecked Sendable {
    private var callIndex = 0

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        try await call(functionName: functionName, jsonBody: Data())
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        callIndex += 1
        if callIndex == 1 {
            let rows = (0..<12).map { i in
                """
                {"message_id":"m\(i)","sender_id":null,"image_url":"https://example.com/\(i).jpg","created_at":"2026-03-\(String(format: "%02d", i + 1))T00:00:00Z"}
                """
            }
            return Data("[\(rows.joined(separator: ","))]".utf8)
        }
        return Data(
            """
            [{"message_id":"m12","sender_id":null,"image_url":"https://example.com/12.jpg","created_at":"2026-02-28T00:00:00Z"}]
            """.utf8
        )
    }
}
