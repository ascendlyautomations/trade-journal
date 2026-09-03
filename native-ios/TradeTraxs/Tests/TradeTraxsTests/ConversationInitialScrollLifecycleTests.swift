import XCTest
@testable import TradeTraxs

@MainActor
final class ConversationInitialScrollLifecycleTests: XCTestCase {
    private let conversationID = ConversationID("conv-initial-scroll")
    private let messageOld = MessageID("msg-old")
    private let messageNew = MessageID("msg-new")

    func testCoordinatorPaginationCommandsIgnoredWhileInitialScrollPending() {
        let coordinator = makeCoordinator()

        coordinator.beginPagination(anchorMessageID: messageOld, conversationID: conversationID)
        coordinator.handle(.paginationApplied, conversationID: conversationID)

        XCTAssertEqual(coordinator.mode, .initialPositionPending)
        XCTAssertNil(coordinator.desiredScrollPositionID)
    }

    func testNearBottomIgnoredUntilInitialScrollCompletes() {
        let coordinator = makeCoordinator()

        coordinator.reportNearBottom(false, conversationID: conversationID)

        XCTAssertEqual(coordinator.mode, .initialPositionPending)
    }

    func testKeyboardIgnoredUntilInitialScrollCompletes() {
        let coordinator = makeCoordinator()
        let generation = coordinator.scrollCommandGeneration

        coordinator.reportKeyboardVisible(true, conversationID: conversationID)

        XCTAssertEqual(coordinator.scrollCommandGeneration, generation)
        XCTAssertNil(coordinator.desiredScrollPositionID)
    }

    func testCompleteInitialScrollPositionEnablesNearBottomTracking() {
        let coordinator = makeCoordinator()

        coordinator.completeInitialScrollPosition(conversationID: conversationID)

        XCTAssertEqual(coordinator.mode, .bottomPinned)
        coordinator.reportNearBottom(false, conversationID: conversationID)
        XCTAssertEqual(coordinator.mode, .readingHistory)
    }

    func testPaginationAfterInitialScrollCompleteIssuesAnchorScroll() {
        let coordinator = makeCoordinator()
        coordinator.completeInitialScrollPosition(conversationID: conversationID)

        coordinator.beginPagination(anchorMessageID: messageOld, conversationID: conversationID)
        coordinator.handle(.paginationApplied, conversationID: conversationID)

        XCTAssertEqual(coordinator.mode, .readingHistory)
        XCTAssertEqual(coordinator.desiredScrollPositionID, messageOld.rawValue)
    }

    private func makeCoordinator() -> ConversationScrollCoordinator {
        let coordinator = ConversationScrollCoordinator()
        coordinator.resetForConversation(conversationID)
        coordinator.handle(
            .bootstrapApplied(newestMessageID: messageNew, isEmpty: false),
            conversationID: conversationID
        )
        return coordinator
    }
}
