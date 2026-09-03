import Foundation
import Observation

enum ConversationScrollAnchorID {
    static let bottom = "conversation-scroll-bottom"
}

/// Explicit scroll ownership for DM / group conversation threads.
@Observable
@MainActor
final class ConversationScrollCoordinator {
    enum Mode: Equatable {
        case initialPositionPending
        case bottomPinned
        case readingHistory
        case paginationAnchorPending(anchorMessageID: MessageID)
        case jumpToLatestRequested
    }

    enum Event: Equatable {
        case bootstrapApplied(newestMessageID: MessageID?, isEmpty: Bool)
        case cacheApplied(newestMessageID: MessageID?, isEmpty: Bool)
        case layoutReady(newestMessageID: MessageID?, isEmpty: Bool)
        case outgoingMessageInserted(messageID: MessageID)
        case optimisticConfirmed(from: MessageID, to: MessageID)
        case incomingMessageInserted(messageID: MessageID)
        case paginationStarted(anchorMessageID: MessageID)
        case paginationApplied
        case userNearBottom(Bool)
        case keyboardChanged(isVisible: Bool)
        case jumpToLatestTapped
    }

    private(set) var mode: Mode = .initialPositionPending
    private(set) var showsNewMessagesIndicator = false
    private(set) var desiredScrollPositionID: String?
    private(set) var desiredScrollAnimated = false
    private(set) var scrollCommandGeneration: UInt64 = 0

    private var boundConversationID: ConversationID?
    private var newestMessageID: MessageID?
    private var pendingInitialScroll = true
    private var suppressIncomingScroll = false
    private var lastOutgoingScrollTarget: MessageID?

    var newestMessageIDForLayout: MessageID? { newestMessageID }

    /// True while the thread still needs its one-time open/reopen positioning pass.
    var awaitsInitialScrollPosition: Bool {
        pendingInitialScroll && (mode == .initialPositionPending || mode == .jumpToLatestRequested)
    }

    func resetForConversation(_ conversationID: ConversationID) {
        boundConversationID = conversationID
        mode = .initialPositionPending
        showsNewMessagesIndicator = false
        desiredScrollPositionID = nil
        desiredScrollAnimated = false
        newestMessageID = nil
        pendingInitialScroll = true
        suppressIncomingScroll = false
        lastOutgoingScrollTarget = nil
        scrollCommandGeneration &+= 1
    }

    func handle(
        _ event: Event,
        conversationID: ConversationID
    ) {
        guard boundConversationID == conversationID else { return }
        switch event {
        case .bootstrapApplied(let newest, let isEmpty),
             .cacheApplied(let newest, let isEmpty):
            handleContentApplied(newestMessageID: newest, isEmpty: isEmpty)

        case .layoutReady(let newest, let isEmpty):
            if let newest {
                self.newestMessageID = newest
            }
            guard pendingInitialScroll else { return }
            guard mode == .initialPositionPending || mode == .jumpToLatestRequested else { return }
            if isEmpty {
                pendingInitialScroll = false
                mode = .bottomPinned
                return
            }
            // Wait until the newest message row is laid out before the one-time open scroll.
            guard let targetID = newest else { return }
            pendingInitialScroll = false
            issueScroll(to: .message(targetID), animated: false)
            mode = .bottomPinned
            showsNewMessagesIndicator = false

        case .outgoingMessageInserted(let messageID):
            newestMessageID = messageID
            lastOutgoingScrollTarget = messageID
            guard shouldFollowTailForOutgoing else { return }
            issueScroll(to: .message(messageID), animated: true)
            mode = .bottomPinned
            showsNewMessagesIndicator = false

        case .optimisticConfirmed(let from, let to):
            if desiredScrollPositionID == from.rawValue {
                desiredScrollPositionID = to.rawValue
                desiredScrollAnimated = false
                scrollCommandGeneration &+= 1
            }
            if lastOutgoingScrollTarget == from {
                lastOutgoingScrollTarget = to
            }
            if newestMessageID == from {
                newestMessageID = to
            }
            suppressIncomingScroll = true

        case .incomingMessageInserted(let messageID):
            guard !suppressIncomingScroll else {
                suppressIncomingScroll = false
                newestMessageID = messageID
                return
            }
            newestMessageID = messageID
            switch mode {
            case .bottomPinned, .jumpToLatestRequested:
                issueScroll(to: .message(messageID), animated: true)
                mode = .bottomPinned
                showsNewMessagesIndicator = false
            case .initialPositionPending:
                break
            case .readingHistory, .paginationAnchorPending:
                showsNewMessagesIndicator = true
            }

        case .paginationStarted(let anchorMessageID):
            guard !pendingInitialScroll else { return }
            mode = .paginationAnchorPending(anchorMessageID: anchorMessageID)
            showsNewMessagesIndicator = false

        case .paginationApplied:
            guard !pendingInitialScroll else { return }
            guard case .paginationAnchorPending(let anchor) = mode else { return }
            issueScroll(to: .message(anchor), animated: false)
            mode = .readingHistory

        case .userNearBottom(let isNearBottom):
            guard !pendingInitialScroll else { return }
            if isNearBottom {
                mode = .bottomPinned
                showsNewMessagesIndicator = false
            } else if mode == .bottomPinned {
                mode = .readingHistory
            }

        case .keyboardChanged(let isVisible):
            guard !pendingInitialScroll else { return }
            guard isVisible, mode == .bottomPinned else { return }
            if let newestMessageID {
                issueScroll(to: .message(newestMessageID), animated: false)
            } else {
                issueScroll(to: .bottom, animated: false)
            }

        case .jumpToLatestTapped:
            mode = .jumpToLatestRequested
            pendingInitialScroll = false
            if let newestMessageID {
                issueScroll(to: .message(newestMessageID), animated: true)
            } else {
                issueScroll(to: .bottom, animated: true)
            }
            mode = .bottomPinned
            showsNewMessagesIndicator = false
        }
    }

    func jumpToLatest(conversationID: ConversationID) {
        handle(.jumpToLatestTapped, conversationID: conversationID)
    }

    func beginPagination(anchorMessageID: MessageID, conversationID: ConversationID) {
        handle(.paginationStarted(anchorMessageID: anchorMessageID), conversationID: conversationID)
    }

    func reportLayoutReady(
        newestMessageID: MessageID?,
        isEmpty: Bool,
        conversationID: ConversationID
    ) {
        handle(
            .layoutReady(newestMessageID: newestMessageID, isEmpty: isEmpty),
            conversationID: conversationID
        )
    }

    func reportNearBottom(_ isNearBottom: Bool, conversationID: ConversationID) {
        handle(.userNearBottom(isNearBottom), conversationID: conversationID)
    }

    func reportKeyboardVisible(_ isVisible: Bool, conversationID: ConversationID) {
        handle(.keyboardChanged(isVisible: isVisible), conversationID: conversationID)
    }

    /// Called by the view after Trade Room-style initial `scrollTo` completes.
    func completeInitialScrollPosition(conversationID: ConversationID) {
        guard boundConversationID == conversationID else { return }
        pendingInitialScroll = false
        if mode == .initialPositionPending {
            mode = .bottomPinned
        }
        showsNewMessagesIndicator = false
    }

    // MARK: - Private

    private var shouldFollowTailForOutgoing: Bool {
        switch mode {
        case .initialPositionPending, .bottomPinned, .jumpToLatestRequested:
            return true
        case .readingHistory, .paginationAnchorPending:
            return false
        }
    }

    private func handleContentApplied(newestMessageID: MessageID?, isEmpty: Bool) {
        let previousNewest = self.newestMessageID
        self.newestMessageID = newestMessageID
        if isEmpty {
            pendingInitialScroll = false
            mode = .bottomPinned
            return
        }
        switch mode {
        case .initialPositionPending:
            break
        case .bottomPinned:
            guard let newestMessageID, newestMessageID != previousNewest else { return }
            issueScroll(to: .message(newestMessageID), animated: false)
        case .readingHistory, .paginationAnchorPending:
            if let newestMessageID, newestMessageID != previousNewest {
                showsNewMessagesIndicator = true
            }
        case .jumpToLatestRequested:
            break
        }
    }

    private enum ScrollTarget: Equatable {
        case bottom
        case message(MessageID)
    }

    private func issueScroll(to target: ScrollTarget, animated: Bool) {
        switch target {
        case .bottom:
            desiredScrollPositionID = ConversationScrollAnchorID.bottom
        case .message(let id):
            desiredScrollPositionID = id.rawValue
        }
        desiredScrollAnimated = animated
        scrollCommandGeneration &+= 1
    }
}

#if DEBUG
extension ConversationScrollCoordinator {
    func testing_setMode(_ mode: Mode) {
        self.mode = mode
    }

    func testing_setPendingInitialScroll(_ value: Bool) {
        pendingInitialScroll = value
    }
}
#endif
