import Foundation
import Observation

/// Shared server-backed block / unblock for Profile and DM surfaces.
@Observable
@MainActor
final class UserBlockCoordinator {
    static let shared = UserBlockCoordinator()

    private(set) var statusByUserID: [ProfileID: DmBlockStatus] = [:]

    func cacheStatus(_ status: DmBlockStatus) {
        statusByUserID[status.otherUserID] = status
    }

    private init() {}

    func cachedStatus(for userID: ProfileID) -> DmBlockStatus? {
        statusByUserID[userID]
    }

    func loadStatus(
        otherID: ProfileID,
        messages: any MessageRepository
    ) async -> DmBlockStatus? {
        if let cached = statusByUserID[otherID] {
            return cached
        }
        guard let status = try? await messages.fetchUserBlockStatus(otherID: otherID) else {
            return nil
        }
        statusByUserID[otherID] = status
        return status
    }

    @discardableResult
    func setBlocked(
        otherID: ProfileID,
        conversationID: ConversationID?,
        blocked: Bool,
        messages: any MessageRepository,
        inboxStore: MessagesInboxStore? = nil
    ) async throws -> DmBlockStatus {
        let inboxStore = inboxStore ?? MessagesInboxStore.shared
        let status: DmBlockStatus
        if let conversationID {
            status = try await messages.setDmUserBlock(conversationID: conversationID, blocked: blocked)
        } else {
            status = try await messages.setUserBlock(otherID: otherID, blocked: blocked)
        }
        statusByUserID[otherID] = status

        if blocked {
            inboxStore.removeDirectConversations(with: otherID)
        }

        NotificationCenter.default.post(name: .userBlockListDidChange, object: nil)
        return status
    }
}

extension Notification.Name {
    static let userBlockListDidChange = Notification.Name("tradetraxs.userBlockListDidChange")
    static let dmPrivacyDidChange = Notification.Name("tradetraxs.dmPrivacyDidChange")
    static let mutedAccountsListDidChange = Notification.Name("tradetraxs.mutedAccountsListDidChange")
}
