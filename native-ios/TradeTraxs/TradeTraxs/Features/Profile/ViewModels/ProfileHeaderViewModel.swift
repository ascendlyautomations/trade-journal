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
    private let detailCache: DetailPresentationCache

    var isSharePresented: Bool = false
    var pendingUnfollowConfirm = false
    private(set) var isOpeningMessage = false

    init(
        store: ProfileContentStore,
        messages: any MessageRepository,
        session: any SessionProviding,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache
    ) {
        self.store = store
        self.messages = messages
        self.session = session
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
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
            isRequested: store.isRequested,
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

    /// Screen owns bootstrap — kept for API compatibility; no independent load.
    func onAppear() {}

    /// Header retry is wired by ``ProfileScreenViewModel/retryBootstrap`` via the view.
    var onRetryBootstrap: (() -> Void)?

    func retry() {
        ExperienceHaptics.play(.selection)
        if let onRetryBootstrap {
            onRetryBootstrap()
        } else {
            store.refresh()
        }
    }

    func openSettings() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.pushProfile(.settings(.home))
    }

    func openEditProfile() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.pushProfile(.settings(.profile))
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
        guard let profile = store.profile else { return }
        guard let viewerRaw = await session.currentUserID?.rawValue else { return }
        let viewerID = ProfileID(viewerRaw)

        isOpeningMessage = true
        defer { isOpeningMessage = false }

        if targetID.rawValue.hasPrefix("dev.") || viewerID.rawValue.hasPrefix("dev.") {
            let suffix = targetID.rawValue.replacingOccurrences(of: "dev.follower.", with: "")
            navigationCoordinator.open(.messages(.thread(ConversationID("dev-dm-\(suffix)"))))
            return
        }

        do {
            let result = try await ConversationCreationCoordinator.shared.openDirectConversation(
                viewerID: viewerID,
                recipient: profile,
                messages: messages,
                detailCache: detailCache,
                inboxStore: MessagesInboxStore.shared
            )
            navigationCoordinator.open(.messages(.thread(result.conversation.id)))
        } catch {
            ExperienceHaptics.play(.warning)
        }
    }
}
