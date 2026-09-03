import XCTest
@testable import TradeTraxs

@MainActor
final class ConversationScrollTests: XCTestCase {
    private let conversationA = ConversationID("conv-a")
    private let conversationB = ConversationID("conv-b")
    private let messageOld = MessageID("msg-old")
    private let messageMid = MessageID("msg-mid")
    private let messageNew = MessageID("msg-new")
    private let tempOutgoing = MessageID("temp-outgoing")
    private let confirmedOutgoing = MessageID("confirmed-outgoing")

    private func makeCoordinator(for conversationID: ConversationID) -> ConversationScrollCoordinator {
        let coordinator = ConversationScrollCoordinator()
        coordinator.resetForConversation(conversationID)
        return coordinator
    }

    func testColdThreadOpenScrollsToNewestMessage() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.handle(
            .bootstrapApplied(newestMessageID: messageNew, isEmpty: false),
            conversationID: conversationA
        )

        XCTAssertEqual(coordinator.mode, .initialPositionPending)
        XCTAssertNil(coordinator.desiredScrollPositionID)

        coordinator.completeInitialScrollPosition(conversationID: conversationA)

        XCTAssertEqual(coordinator.mode, .bottomPinned)
        XCTAssertNil(coordinator.desiredScrollPositionID)
    }

    func testWarmCachedThreadOpenScrollsToNewestMessage() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.handle(
            .cacheApplied(newestMessageID: messageNew, isEmpty: false),
            conversationID: conversationA
        )

        XCTAssertEqual(coordinator.mode, .initialPositionPending)
        XCTAssertNil(coordinator.desiredScrollPositionID)

        coordinator.completeInitialScrollPosition(conversationID: conversationA)

        XCTAssertEqual(coordinator.mode, .bottomPinned)
    }

    func testDirectConversationOpensAtNewest() {
        testColdThreadOpenScrollsToNewestMessage()
    }

    func testGroupConversationOpensAtNewest() {
        let groupID = ConversationID("group-alpha")
        let coordinator = makeCoordinator(for: groupID)
        coordinator.handle(
            .bootstrapApplied(newestMessageID: messageNew, isEmpty: false),
            conversationID: groupID
        )
        XCTAssertEqual(coordinator.mode, .initialPositionPending)
        coordinator.completeInitialScrollPosition(conversationID: groupID)
        XCTAssertEqual(coordinator.mode, .bottomPinned)
    }

    func testEmptyConversationDoesNotAttemptInvalidScroll() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.handle(
            .bootstrapApplied(newestMessageID: nil, isEmpty: true),
            conversationID: conversationA
        )

        XCTAssertEqual(coordinator.mode, .bottomPinned)
        XCTAssertNil(coordinator.desiredScrollPositionID)

        coordinator.reportLayoutReady(
            newestMessageID: nil,
            isEmpty: true,
            conversationID: conversationA
        )
        XCTAssertNil(coordinator.desiredScrollPositionID)
    }

    func testOutgoingOptimisticMessageScrollsIntoView() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.testing_setMode(.bottomPinned)
        coordinator.handle(
            .outgoingMessageInserted(messageID: tempOutgoing),
            conversationID: conversationA
        )

        XCTAssertEqual(coordinator.desiredScrollPositionID, tempOutgoing.rawValue)
        XCTAssertTrue(coordinator.desiredScrollAnimated)
    }

    func testConfirmationDoesNotCauseDuplicateJumps() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.testing_setMode(.bottomPinned)
        coordinator.handle(
            .outgoingMessageInserted(messageID: tempOutgoing),
            conversationID: conversationA
        )
        let generationAfterOutgoing = coordinator.scrollCommandGeneration

        coordinator.handle(
            .optimisticConfirmed(from: tempOutgoing, to: confirmedOutgoing),
            conversationID: conversationA
        )

        XCTAssertEqual(coordinator.scrollCommandGeneration, generationAfterOutgoing + 1)
        XCTAssertEqual(coordinator.desiredScrollPositionID, confirmedOutgoing.rawValue)
        XCTAssertFalse(coordinator.desiredScrollAnimated)

        coordinator.handle(
            .incomingMessageInserted(messageID: confirmedOutgoing),
            conversationID: conversationA
        )
        XCTAssertEqual(coordinator.scrollCommandGeneration, generationAfterOutgoing + 1)
    }

    func testIncomingMessageAutoScrollsWhileBottomPinned() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.testing_setMode(.bottomPinned)
        coordinator.handle(
            .incomingMessageInserted(messageID: messageNew),
            conversationID: conversationA
        )

        XCTAssertEqual(coordinator.desiredScrollPositionID, messageNew.rawValue)
        XCTAssertTrue(coordinator.desiredScrollAnimated)
        XCTAssertFalse(coordinator.showsNewMessagesIndicator)
    }

    func testIncomingMessageDoesNotAutoScrollWhileReadingHistory() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.testing_setMode(.readingHistory)
        coordinator.handle(
            .incomingMessageInserted(messageID: messageNew),
            conversationID: conversationA
        )

        XCTAssertTrue(coordinator.showsNewMessagesIndicator)
        XCTAssertNotEqual(coordinator.desiredScrollPositionID, messageNew.rawValue)
    }

    func testNewMessageIndicatorAppearsWhileReadingHistory() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.testing_setMode(.readingHistory)
        coordinator.handle(
            .incomingMessageInserted(messageID: messageNew),
            conversationID: conversationA
        )
        XCTAssertTrue(coordinator.showsNewMessagesIndicator)
    }

    func testTappingIndicatorJumpsToNewest() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.testing_setMode(.readingHistory)
        coordinator.jumpToLatest(conversationID: conversationA)

        XCTAssertEqual(coordinator.mode, .bottomPinned)
        XCTAssertFalse(coordinator.showsNewMessagesIndicator)
        XCTAssertEqual(coordinator.desiredScrollPositionID, ConversationScrollAnchorID.bottom)
    }

    func testManuallyReturningToBottomRestoresBottomPinnedState() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.completeInitialScrollPosition(conversationID: conversationA)
        coordinator.testing_setMode(.readingHistory)
        coordinator.reportNearBottom(true, conversationID: conversationA)

        XCTAssertEqual(coordinator.mode, .bottomPinned)
        XCTAssertFalse(coordinator.showsNewMessagesIndicator)
    }

    func testPaginationPreservesVisibleAnchor() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.completeInitialScrollPosition(conversationID: conversationA)
        coordinator.testing_setMode(.readingHistory)
        coordinator.beginPagination(anchorMessageID: messageMid, conversationID: conversationA)

        XCTAssertEqual(coordinator.mode, .paginationAnchorPending(anchorMessageID: messageMid))

        coordinator.handle(.paginationApplied, conversationID: conversationA)

        XCTAssertEqual(coordinator.mode, .readingHistory)
        XCTAssertEqual(coordinator.desiredScrollPositionID, messageMid.rawValue)
        XCTAssertFalse(coordinator.desiredScrollAnimated)
    }

    func testPaginationNeverJumpsToNewest() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.completeInitialScrollPosition(conversationID: conversationA)
        coordinator.beginPagination(anchorMessageID: messageOld, conversationID: conversationA)
        coordinator.handle(.paginationApplied, conversationID: conversationA)

        XCTAssertNotEqual(coordinator.desiredScrollPositionID, ConversationScrollAnchorID.bottom)
        XCTAssertNotEqual(coordinator.desiredScrollPositionID, messageNew.rawValue)
    }

    func testBootstrapRevalidationDoesNotResetReadingPosition() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.testing_setMode(.readingHistory)
        coordinator.handle(
            .bootstrapApplied(newestMessageID: messageNew, isEmpty: false),
            conversationID: conversationA
        )

        XCTAssertEqual(coordinator.mode, .readingHistory)
        XCTAssertTrue(coordinator.showsNewMessagesIndicator)
        XCTAssertNil(coordinator.desiredScrollPositionID)
    }

    func testKeyboardOpeningPreservesBottomPosition() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.handle(
            .bootstrapApplied(newestMessageID: messageNew, isEmpty: false),
            conversationID: conversationA
        )
        coordinator.completeInitialScrollPosition(conversationID: conversationA)
        let generation = coordinator.scrollCommandGeneration
        coordinator.reportKeyboardVisible(true, conversationID: conversationA)

        XCTAssertEqual(coordinator.scrollCommandGeneration, generation + 1)
        XCTAssertEqual(coordinator.desiredScrollPositionID, messageNew.rawValue)
        XCTAssertFalse(coordinator.desiredScrollAnimated)
    }

    func testKeyboardDoesNotForceJumpWhileReadingHistory() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.testing_setMode(.readingHistory)
        let generation = coordinator.scrollCommandGeneration
        coordinator.reportKeyboardVisible(true, conversationID: conversationA)

        XCTAssertEqual(coordinator.scrollCommandGeneration, generation)
        XCTAssertNil(coordinator.desiredScrollPositionID)
    }

    func testSwitchingConversationsResetsInitialPositionState() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.testing_setMode(.bottomPinned)
        coordinator.resetForConversation(conversationB)

        XCTAssertEqual(coordinator.mode, .initialPositionPending)
        XCTAssertFalse(coordinator.showsNewMessagesIndicator)
        XCTAssertNil(coordinator.desiredScrollPositionID)
    }

    func testLateResponseFromConversationACannotScrollConversationB() {
        let coordinator = makeCoordinator(for: conversationB)
        coordinator.handle(
            .incomingMessageInserted(messageID: messageNew),
            conversationID: conversationA
        )

        XCTAssertNil(coordinator.desiredScrollPositionID)
        XCTAssertEqual(coordinator.mode, .initialPositionPending)
    }

    func testReopeningConversationStartsAtNewestMessage() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.testing_setMode(.readingHistory)
        coordinator.resetForConversation(conversationA)
        coordinator.handle(
            .bootstrapApplied(newestMessageID: messageNew, isEmpty: false),
            conversationID: conversationA
        )

        XCTAssertEqual(coordinator.mode, .initialPositionPending)
        coordinator.completeInitialScrollPosition(conversationID: conversationA)
        XCTAssertEqual(coordinator.mode, .bottomPinned)
    }

    func testBootstrapDoesNotIssueInitialScrollCommand() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.handle(
            .bootstrapApplied(newestMessageID: messageNew, isEmpty: false),
            conversationID: conversationA
        )

        XCTAssertNil(coordinator.desiredScrollPositionID)
        XCTAssertTrue(coordinator.awaitsInitialScrollPosition)
    }

    func testLayoutReadyIgnoredAfterInitialScrollCompleted() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.handle(
            .bootstrapApplied(newestMessageID: messageMid, isEmpty: false),
            conversationID: conversationA
        )
        coordinator.completeInitialScrollPosition(conversationID: conversationA)
        let generation = coordinator.scrollCommandGeneration

        coordinator.reportLayoutReady(
            newestMessageID: messageNew,
            isEmpty: false,
            conversationID: conversationA
        )

        XCTAssertEqual(coordinator.scrollCommandGeneration, generation)
    }

    func testOutgoingDoesNotScrollWhileReadingHistory() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.testing_setMode(.readingHistory)
        coordinator.handle(
            .outgoingMessageInserted(messageID: tempOutgoing),
            conversationID: conversationA
        )

        XCTAssertNil(coordinator.desiredScrollPositionID)
    }

    func testJumpToLatestUsesNewestMessageIDWhenAvailable() {
        let coordinator = makeCoordinator(for: conversationA)
        coordinator.handle(
            .bootstrapApplied(newestMessageID: messageNew, isEmpty: false),
            conversationID: conversationA
        )
        coordinator.completeInitialScrollPosition(conversationID: conversationA)
        coordinator.testing_setMode(.readingHistory)
        coordinator.jumpToLatest(conversationID: conversationA)

        XCTAssertEqual(coordinator.desiredScrollPositionID, messageNew.rawValue)
    }

    func testLayoutReadyCanCompleteInitialScrollWhenBootstrapDeferred() {
        let coordinator = makeCoordinator(for: conversationA)

        coordinator.reportLayoutReady(
            newestMessageID: nil,
            isEmpty: false,
            conversationID: conversationA
        )
        XCTAssertTrue(coordinator.awaitsInitialScrollPosition)
        XCTAssertNil(coordinator.desiredScrollPositionID)

        coordinator.reportLayoutReady(
            newestMessageID: messageNew,
            isEmpty: false,
            conversationID: conversationA
        )
        XCTAssertFalse(coordinator.awaitsInitialScrollPosition)
        XCTAssertEqual(coordinator.desiredScrollPositionID, messageNew.rawValue)
    }
}
