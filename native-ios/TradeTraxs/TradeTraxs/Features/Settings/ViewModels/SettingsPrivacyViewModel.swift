import Foundation
import Observation

@Observable
@MainActor
final class SettingsPrivacyViewModel {
    private let profiles: any ProfileRepository
    private let messages: any MessageRepository
    private let session: any SessionProviding
    private let profilePrivacy: SettingsProfileViewModel

    private(set) var dmPrivacy: DmPrivacy = .everyone
    private(set) var blockedCount = 0
    private(set) var mutedCount = 0
    private(set) var isLoadingLists = false
    private(set) var errorMessage: String?

    init(
        profiles: any ProfileRepository,
        messages: any MessageRepository,
        session: any SessionProviding,
        profilePrivacy: SettingsProfileViewModel
    ) {
        self.profiles = profiles
        self.messages = messages
        self.session = session
        self.profilePrivacy = profilePrivacy
    }

    var draftIsPrivate: Bool {
        get { profilePrivacy.draftIsPrivate }
        set { profilePrivacy.setPrivate(newValue) }
    }

    var profileErrorMessage: String? {
        profilePrivacy.errorMessage
    }

    var isProfileLoading: Bool {
        profilePrivacy.isLoading
    }

    func loadIfNeeded() {
        profilePrivacy.loadIfNeeded()
    }

    func refresh() async {
        await profilePrivacy.refresh()
        await refreshSummary()
    }

    func refreshSummary() async {
        isLoadingLists = true
        defer { isLoadingLists = false }
        do {
            guard await session.currentUserID != nil else {
                errorMessage = "Sign in to continue."
                return
            }
            async let privacyTask = profiles.ownerDmPrivacy()
            async let blockedTask = messages.fetchBlockedAccounts()
            async let mutedTask = messages.fetchMutedDirectMessagePeers()
            dmPrivacy = try await privacyTask
            blockedCount = try await blockedTask.count
            mutedCount = try await mutedTask.count
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func updateDmPrivacy(_ privacy: DmPrivacy) {
        let previous = dmPrivacy
        dmPrivacy = privacy
        Task {
            do {
                dmPrivacy = try await profiles.updateDmPrivacy(privacy)
                NotificationCenter.default.post(name: .dmPrivacyDidChange, object: nil)
                errorMessage = nil
            } catch {
                dmPrivacy = previous
                errorMessage = "Couldn't update messaging privacy."
                ExperienceHaptics.play(.warning)
            }
        }
    }
}

@Observable
@MainActor
final class SettingsBlockedAccountsViewModel {
    private let messages: any MessageRepository
    private let navigationCoordinator: NavigationCoordinator

    private(set) var items: [BlockedAccount] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var actionInFlight: ProfileID?

    init(messages: any MessageRepository, navigationCoordinator: NavigationCoordinator) {
        self.messages = messages
        self.navigationCoordinator = navigationCoordinator
    }

    func loadIfNeeded() {
        guard items.isEmpty else { return }
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = items.isEmpty
        defer { isLoading = false }
        do {
            items = try await messages.fetchBlockedAccounts()
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func unblock(_ account: BlockedAccount) {
        guard actionInFlight == nil else { return }
        actionInFlight = account.id
        Task {
            defer { actionInFlight = nil }
            do {
                _ = try await UserBlockCoordinator.shared.setBlocked(
                    otherID: account.id,
                    conversationID: nil,
                    blocked: false,
                    messages: messages
                )
                items.removeAll { $0.id == account.id }
                NotificationCenter.default.post(name: .userBlockListDidChange, object: nil)
                ExperienceHaptics.play(.success)
            } catch {
                errorMessage = UserFacingError.message(for: error)
                ExperienceHaptics.play(.warning)
            }
        }
    }

    func openProfile(_ account: BlockedAccount) {
        navigationCoordinator.pushSettingsProfilePreview(account.id)
    }
}

@Observable
@MainActor
final class SettingsMutedAccountsViewModel {
    private let messages: any MessageRepository
    private let navigationCoordinator: NavigationCoordinator

    private(set) var items: [MutedDirectMessagePeer] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var actionInFlight: ProfileID?

    init(messages: any MessageRepository, navigationCoordinator: NavigationCoordinator) {
        self.messages = messages
        self.navigationCoordinator = navigationCoordinator
    }

    func loadIfNeeded() {
        guard items.isEmpty else { return }
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = items.isEmpty
        defer { isLoading = false }
        do {
            items = try await messages.fetchMutedDirectMessagePeers()
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func unmute(_ peer: MutedDirectMessagePeer) {
        guard actionInFlight == nil else { return }
        actionInFlight = peer.id
        Task {
            defer { actionInFlight = nil }
            do {
                try await messages.setConversationNotificationsEnabled(
                    conversationID: peer.conversationID,
                    enabled: true
                )
                MessagesInboxStore.shared.applyConversationMute(
                    conversationID: peer.conversationID,
                    isMuted: false
                )
                items.removeAll { $0.id == peer.id }
                NotificationCenter.default.post(name: .mutedAccountsListDidChange, object: nil)
                ExperienceHaptics.play(.success)
            } catch {
                errorMessage = UserFacingError.message(for: error)
                ExperienceHaptics.play(.warning)
            }
        }
    }

    func openProfile(_ peer: MutedDirectMessagePeer) {
        navigationCoordinator.pushSettingsProfilePreview(peer.id)
    }
}

private extension NavigationCoordinator {
    func pushSettingsProfilePreview(_ profileID: ProfileID) {
        pushProfile(.otherProfile(profileID))
    }
}
