import Foundation
import Observation
import SwiftUI

/// Screen-facing façade over ``ProfileContentStore`` for the unified Profile header.
@Observable
@MainActor
final class ProfileHeaderViewModel {
    private let store: ProfileContentStore
    private let messages: any MessageRepository
    private let session: any SessionProviding
    private let navigationCoordinator: NavigationCoordinator

    var isSharePresented: Bool = false
    var pendingUnfollowConfirm = false
    private(set) var isOpeningMessage = false

    init(
        store: ProfileContentStore,
        messages: any MessageRepository,
        session: any SessionProviding,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.store = store
        self.messages = messages
        self.session = session
        self.navigationCoordinator = navigationCoordinator
    }

    var phase: ProfileContentStore.Phase { store.phase }
    var profile: Profile? { store.profile }
    var stats: ProfileStats? { store.stats }
    var avatarImage: Image? { store.avatarImage }
    var initials: String { store.initials }
    var errorMessage: String? { store.errorMessage }
    var isLoading: Bool { store.phase == .loading && store.profile == nil }
    var isOwner: Bool { store.isOwner }
    var isFollowing: Bool { store.isFollowing }
    var hasTradeRoom: Bool { store.hasTradeRoom }
    var ownedTradeRoom: TradeRoom? { store.ownedTradeRoom }

    var actionMode: ProfileActionRow.Mode {
        if store.isOwner {
            return .owner(hasTradeRoom: store.hasTradeRoom)
        }
        return .visitor(
            isFollowing: store.isFollowing,
            showsTradeRoom: store.canShowVisitorTradeRoomCTA
        )
    }

    var shareURL: URL? {
        guard let username = profile?.username, !username.isEmpty else { return nil }
        return URL(string: "https://www.tradetraxs.com/\(username)")
    }

    var shareText: String {
        guard let profile else { return "TradeTraxs" }
        return "\(profile.displayName) (@\(profile.username)) on TradeTraxs"
    }

    func onAppear() {
        store.loadIfNeeded()
    }

    func retry() {
        ExperienceHaptics.play(.selection)
        store.refresh()
    }

    func openSettings() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.profile(.settings(nil)))
    }

    func openEditProfile() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.profile(.settings(.profile)))
    }

    func presentShare() {
        ExperienceHaptics.play(.selection)
        isSharePresented = true
    }

    func openFollowers() {
        guard let profileID = store.resolvedProfileID ?? store.profile?.id else { return }
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.profile(.followers(profileID)))
    }

    func openFollowing() {
        guard let profileID = store.resolvedProfileID ?? store.profile?.id else { return }
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.profile(.following(profileID)))
    }

    func followAction() {
        if store.isFollowing {
            pendingUnfollowConfirm = true
            return
        }
        Task { await store.toggleFollow() }
    }

    func confirmUnfollow() async {
        pendingUnfollowConfirm = false
        if store.isFollowing {
            await store.toggleFollow()
        }
    }

    func openMessage() {
        guard !store.isOwner, !isOpeningMessage else { return }
        Task { await openOrCreateConversation() }
    }

    func openTradeRoom() {
        guard let room = store.ownedTradeRoom else { return }
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.profile(.room(room.id)))
    }

    func createTradeRoom() {
        ExperienceHaptics.play(.selection)
        // Create UI arrives with Rooms feature — rooms root is the permanent gateway.
        navigationCoordinator.open(.profile(.rooms))
    }

    // MARK: - Private

    private func openOrCreateConversation() async {
        guard let targetID = store.resolvedProfileID ?? store.profile?.id else { return }
        guard let viewerRaw = await session.currentUserID?.rawValue else { return }
        let viewerID = ProfileID(viewerRaw)

        isOpeningMessage = true
        defer { isOpeningMessage = false }

        if targetID.rawValue.hasPrefix("dev.") || viewerID.rawValue.hasPrefix("dev.") {
            let conversationID = ConversationID("dev-dm-\(viewerID.rawValue)-\(targetID.rawValue)")
            navigationCoordinator.open(.messages(.thread(conversationID)))
            return
        }

        do {
            let page = try await messages.conversations(page: PageRequest(limit: 100))
            let participants = Set([viewerID, targetID])
            if let existing = page.items.first(where: {
                Set($0.participantProfileIDs) == participants
            }) {
                navigationCoordinator.open(.messages(.thread(existing.id)))
                return
            }
            let created = try await messages.createConversation(
                participantIDs: [viewerID, targetID]
            )
            navigationCoordinator.open(.messages(.thread(created.id)))
        } catch {
            ExperienceHaptics.play(.warning)
        }
    }
}
