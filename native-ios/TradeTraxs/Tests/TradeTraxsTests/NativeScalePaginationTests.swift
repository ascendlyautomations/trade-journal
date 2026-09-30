import XCTest
@testable import TradeTraxs

final class MessagingInboxPaginationTests: XCTestCase {
    func testRealtimeWatchCapsAtForty() {
        let ids = (0..<120).map { ConversationID("conv-\($0)") }
        let conversations = ids.map { id in
            Conversation(
                id: id,
                participantProfileIDs: [],
                title: nil,
                peerUsername: nil,
                avatar: nil,
                isGroup: false,
                isPinned: false,
                lastMessagePreview: nil,
                lastMessageAt: nil,
                lastMessageID: nil,
                unreadCount: 0,
                isMuted: false,
                updatedAt: .distantPast
            )
        }
        let watched = MessagingInboxPagination.conversationIDsForRealtimeWatch(conversations)
        XCTAssertEqual(watched.count, 40)
        XCTAssertEqual(watched.first, "conv-0")
        XCTAssertEqual(watched.last, "conv-39")
    }

    func testRealtimeWatchIncludesActiveThreadOutsideWindow() {
        let conversations = (0..<50).map { index in
            Conversation(
                id: ConversationID("conv-\(index)"),
                participantProfileIDs: [],
                title: nil,
                peerUsername: nil,
                avatar: nil,
                isGroup: false,
                isPinned: false,
                lastMessagePreview: nil,
                lastMessageAt: nil,
                lastMessageID: nil,
                unreadCount: 0,
                isMuted: false,
                updatedAt: .distantPast
            )
        }
        let active = ConversationID("conv-49")
        let watched = MessagingInboxPagination.conversationIDsForRealtimeWatch(
            conversations,
            alwaysInclude: active
        )
        XCTAssertEqual(watched.count, 41)
        XCTAssertTrue(watched.contains("conv-49"))
    }

    func testPageSizeIsForty() {
        XCTAssertEqual(MessagingInboxPagination.pageSize, 40)
    }
}

final class FollowListPaginationTests: XCTestCase {
    func testPageSizeIsForty() {
        XCTAssertEqual(FollowListPagination.pageSize, 40)
    }
}
