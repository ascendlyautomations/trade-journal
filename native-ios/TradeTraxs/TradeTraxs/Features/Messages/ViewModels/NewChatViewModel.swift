import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class NewChatViewModel {
    enum Mode: Equatable {
        case chooser
        case personal
        case group
    }

    enum Phase: Equatable {
        case idle
        case searching
        case opening
        case failed(String)
    }

    private(set) var mode: Mode = .chooser
    private(set) var phase: Phase = .idle
    private(set) var results: [Profile] = []
    private(set) var selectedGroupMembers: [Profile] = []
    private(set) var followingProfiles: [Profile] = []
    private(set) var suggestedProfiles: [Profile] = []
    private(set) var isLoadingSuggestions = false
    private(set) var isLoadingMoreSuggested = false
    private(set) var canLoadMoreSuggested = false
    var searchText = ""
    var groupName = ""
    private(set) var groupAvatarPreview: UIImage?
    private(set) var pendingGroupAvatarJPEG: Data?

    private let messages: any MessageRepository
    private let search: any SearchRepository
    private let profiles: any ProfileRepository
    private let explore: any ExploreRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let inboxStore: MessagesInboxStore
    private let creationCoordinator: ConversationCreationCoordinator
    private let uploadService: (any UploadService)?
    private let objectStorage: (any ObjectStorageProviding)?

    private var viewerID: ProfileID?
    private var searchTask: Task<Void, Never>?
    private var suggestedNextCursor: String?
    private var searchGeneration: UInt64 = 0
    private var openingProfileID: ProfileID?
    private var isCreatingGroup = false
    private var loadMoreSuggestedTask: Task<Void, Never>?

    private static let suggestedPageSize = 15
    private static let hideSuggestedWhenFollowingCount = 10

    init(
        messages: any MessageRepository,
        search: any SearchRepository,
        profiles: any ProfileRepository,
        explore: any ExploreRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        inboxStore: MessagesInboxStore? = nil,
        creationCoordinator: ConversationCreationCoordinator? = nil,
        uploadService: (any UploadService)? = nil,
        objectStorage: (any ObjectStorageProviding)? = nil
    ) {
        self.messages = messages
        self.search = search
        self.profiles = profiles
        self.explore = explore
        self.session = session
        self.detailCache = detailCache
        self.inboxStore = inboxStore ?? MessagesInboxStore.shared
        self.creationCoordinator = creationCoordinator ?? .shared
        self.uploadService = uploadService
        self.objectStorage = objectStorage
    }

    var normalizedQuery: String {
        SearchQueryNormalization.normalizePeopleQuery(searchText)
    }

    var isSearching: Bool {
        !normalizedQuery.isEmpty
    }

    var visibleResults: [Profile] {
        results
    }

    var showsFollowingSection: Bool {
        !isSearching && !followingProfiles.isEmpty
    }

    var showsSuggestedSection: Bool {
        !isSearching && followingProfiles.count < Self.hideSuggestedWhenFollowingCount
    }

    var showsSuggestedSeeMore: Bool {
        showsSuggestedSection && canLoadMoreSuggested && !isLoadingSuggestions
    }

    var canCreateGroup: Bool {
        selectedGroupMembers.count >= 2 && !isCreatingGroup && phase != .opening
    }

    var prompt: String {
        switch phase {
        case .failed:
            return "Search unavailable"
        default:
            break
        }
        if isLoadingSuggestions, normalizedQuery.isEmpty {
            return "Loading people…"
        }
        if mode == .group, selectedGroupMembers.isEmpty, normalizedQuery.isEmpty {
            return "Select group members"
        }
        if normalizedQuery.isEmpty { return "Search people" }
        if phase == .searching { return "Searching…" }
        return "No matching people"
    }

    var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    func presentPersonalChat() {
        mode = .personal
        searchText = ""
        results = []
        phase = .idle
    }

    func presentGroupChat() {
        mode = .group
        searchText = ""
        results = []
        selectedGroupMembers = []
        groupName = ""
        clearGroupAvatar()
        phase = .idle
    }

    func setGroupAvatar(from image: UIImage) {
        groupAvatarPreview = image
        pendingGroupAvatarJPEG = MediaImagePreparation.avatarJPEGData(from: image)
    }

    func clearGroupAvatar() {
        groupAvatarPreview = nil
        pendingGroupAvatarJPEG = nil
    }

    func backToChooser() {
        searchTask?.cancel()
        mode = .chooser
        searchText = ""
        results = []
        selectedGroupMembers = []
        groupName = ""
        clearGroupAvatar()
        phase = .idle
        openingProfileID = nil
        isCreatingGroup = false
    }

    func prepare() async {
        isLoadingSuggestions = true
        followingProfiles = []
        suggestedProfiles = []
        suggestedNextCursor = nil
        canLoadMoreSuggested = false
        defer { isLoadingSuggestions = false }

        if let raw = await session.currentUserID?.rawValue {
            viewerID = ProfileID(raw)
        }
        guard let viewerID else { return }

        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) {
            await reloadSectionsForDevelopment(viewerID: viewerID)
            return
        }

        await FeedBlockedAuthorsFilter.shared.syncFromServer(messages: messages, force: false)
        await reloadFollowingAndSuggested(resetSuggestedPagination: true)
    }

    func handleFollowRelationshipChange() async {
        guard !isSearching else { return }
        if let viewerID, MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) {
            await reloadSectionsForDevelopment(viewerID: viewerID)
            return
        }
        await reloadFollowingAndSuggested(resetSuggestedPagination: true)
    }

    func handleBlockListChange() {
        Task { await handleFollowRelationshipChange() }
    }

    func loadMoreSuggested() async {
        guard showsSuggestedSection,
              canLoadMoreSuggested,
              !isLoadingMoreSuggested,
              loadMoreSuggestedTask == nil
        else { return }

        isLoadingMoreSuggested = true
        loadMoreSuggestedTask = Task {
            defer {
                isLoadingMoreSuggested = false
                loadMoreSuggestedTask = nil
            }
            await loadSuggestedPage(reset: false)
        }
        await loadMoreSuggestedTask?.value
    }

    func searchChanged() {
        searchTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        let query = normalizedQuery
        guard !query.isEmpty else {
            results = []
            if phase == .searching { phase = .idle }
            return
        }

        if let viewerID, MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) {
            let lowered = query.lowercased()
            results = (FollowListFixtures.followers(owner: viewerID) + FollowListFixtures.following(owner: viewerID))
                .uniqued(by: \.id)
                .filter { $0.id != viewerID }
                .filter {
                    $0.displayName.lowercased().contains(lowered)
                        || $0.username.lowercased().contains(lowered)
                }
            phase = .idle
            return
        }

        phase = .searching
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled, generation == searchGeneration else { return }
            do {
                let page = try await search.search(
                    query: query,
                    kinds: [.profile],
                    page: PageRequest(limit: 24),
                    excludingProfileID: viewerID
                )
                guard !Task.isCancelled, generation == searchGeneration else { return }
                let ids = page.items.compactMap { result -> ProfileID? in
                    guard result.kind == .profile, let id = result.profileID, id != viewerID else {
                        return nil
                    }
                    return id
                }
                var byID: [ProfileID: Profile] = [:]
                let fetched = (try? await SessionProfileStore.shared.profiles(
                    ids: ids,
                    detailCache: detailCache,
                    repository: self.profiles
                )) ?? []
                for profile in fetched {
                    byID[profile.id] = profile
                }
                var profiles: [Profile] = []
                for result in page.items where result.kind == .profile {
                    guard let id = result.profileID, id != viewerID else { continue }
                    if let profile = byID[id] {
                        profiles.append(profile)
                    } else {
                        profiles.append(
                            Profile(
                                id: id,
                                userID: UserID(id.rawValue),
                                username: result.title,
                                displayName: result.subtitle ?? result.title,
                                bio: nil,
                                avatar: nil,
                                traderType: nil,
                                tradingStyle: nil,
                                primaryMarket: nil,
                                startedTradingAt: nil,
                                isPrivate: false,
                                isCreator: false,
                                createdAt: .now
                            )
                        )
                    }
                }
                guard generation == searchGeneration else { return }
                results = profiles
                phase = .idle
            } catch {
                guard !Task.isCancelled, generation == searchGeneration else { return }
                results = []
                phase = .failed(MessagesInboxSupport.message(for: error))
            }
        }
    }

    func dismiss() {
        searchTask?.cancel()
        searchTask = nil
        loadMoreSuggestedTask?.cancel()
        loadMoreSuggestedTask = nil
        searchGeneration &+= 1
        results = []
        searchText = ""
        selectedGroupMembers = []
        groupName = ""
        mode = .chooser
        phase = .idle
        openingProfileID = nil
        isCreatingGroup = false
        isLoadingSuggestions = false
        isLoadingMoreSuggested = false
        canLoadMoreSuggested = false
        suggestedNextCursor = nil
        followingProfiles = []
        suggestedProfiles = []
    }

    func isGroupMemberSelected(_ profile: Profile) -> Bool {
        selectedGroupMembers.contains { $0.id == profile.id }
    }

    func toggleGroupMember(_ profile: Profile) {
        guard profile.id != viewerID else { return }
        if let index = selectedGroupMembers.firstIndex(where: { $0.id == profile.id }) {
            selectedGroupMembers.remove(at: index)
        } else {
            selectedGroupMembers.append(profile)
        }
        ExperienceHaptics.play(.selection)
    }

    func removeGroupMember(_ profile: Profile) {
        selectedGroupMembers.removeAll { $0.id == profile.id }
    }

    /// Opens an existing 1:1 conversation or creates one, never duplicates.
    func select(_ profile: Profile) async -> Conversation? {
        guard let viewerID else { return nil }
        guard openingProfileID == nil else { return nil }
        openingProfileID = profile.id
        ExperienceHaptics.play(.selection)
        phase = .opening
        defer {
            openingProfileID = nil
            if case .opening = phase { phase = .idle }
        }

        do {
            let result = try await creationCoordinator.openDirectConversation(
                viewerID: viewerID,
                recipient: profile,
                messages: messages,
                detailCache: detailCache,
                inboxStore: inboxStore
            )
            #if DEBUG
            ConversationCreationTelemetry.navigationCompleted()
            #endif
            return result.conversation
        } catch ConversationCreationCoordinator.CreationError.blockedRecipient {
            phase = .failed("Direct messaging is unavailable while a user block is active.")
            ExperienceHaptics.play(.warning)
            return nil
        } catch {
            phase = .failed(MessagesInboxSupport.message(for: error))
            ExperienceHaptics.play(.warning)
            return nil
        }
    }

    func createGroup() async -> Conversation? {
        guard let viewerID, canCreateGroup, !isCreatingGroup else { return nil }
        isCreatingGroup = true
        phase = .opening
        defer {
            isCreatingGroup = false
            if case .opening = phase { phase = .idle }
        }

        do {
            let result = try await creationCoordinator.createGroupConversation(
                viewerID: viewerID,
                recipients: selectedGroupMembers,
                name: groupName.nilIfEmpty,
                avatarJPEG: pendingGroupAvatarJPEG,
                uploadService: uploadService,
                objectStorage: objectStorage,
                messages: messages,
                detailCache: detailCache,
                inboxStore: inboxStore
            )
            #if DEBUG
            ConversationCreationTelemetry.navigationCompleted()
            #endif
            return result.conversation
        } catch ConversationCreationCoordinator.CreationError.blockedRecipient {
            phase = .failed("Group messaging is unavailable while a user block is active.")
            ExperienceHaptics.play(.warning)
            return nil
        } catch ConversationCreationCoordinator.CreationError.invalidRecipients {
            phase = .failed("Select at least two people for a group chat.")
            ExperienceHaptics.play(.warning)
        } catch {
            phase = .failed(MessagesInboxSupport.message(for: error))
            ExperienceHaptics.play(.warning)
        }
        return nil
    }

    // MARK: - Sections

    private func reloadSectionsForDevelopment(viewerID: ProfileID) async {
        let following = FollowListFixtures.following(owner: viewerID)
        followingProfiles = filterDiscoverableCandidates(following, viewerID: viewerID)
        for profile in followingProfiles { detailCache.seed(profile) }

        if followingProfiles.count >= Self.hideSuggestedWhenFollowingCount {
            suggestedProfiles = []
            canLoadMoreSuggested = false
            suggestedNextCursor = nil
            return
        }

        await loadSuggestedPage(reset: true)
    }

    private func reloadFollowingAndSuggested(resetSuggestedPagination: Bool) async {
        guard let viewerID else { return }

        do {
            let following = try await loadAllFollowing(for: viewerID)
            followingProfiles = filterDiscoverableCandidates(following, viewerID: viewerID)
            detailCache.seed(following: followingProfiles, for: viewerID)
            for profile in followingProfiles { detailCache.seed(profile) }
        } catch {
            followingProfiles = []
        }

        if followingProfiles.count >= Self.hideSuggestedWhenFollowingCount {
            suggestedProfiles = []
            suggestedNextCursor = nil
            canLoadMoreSuggested = false
            return
        }

        if resetSuggestedPagination {
            suggestedProfiles = []
            suggestedNextCursor = nil
            canLoadMoreSuggested = false
            await loadSuggestedPage(reset: true)
            return
        }

        let followingIDs = Set(followingProfiles.map(\.id))
        suggestedProfiles.removeAll { followingIDs.contains($0.id) }
        suggestedProfiles.removeAll { FeedBlockedAuthorsFilter.shared.contains($0.id) }

        if suggestedProfiles.isEmpty {
            await loadSuggestedPage(reset: true)
        }
    }

    private func loadAllFollowing(for viewerID: ProfileID) async throws -> [Profile] {
        var aggregated: [Profile] = []
        var seen = Set<ProfileID>()
        var cursor: String?
        repeat {
            let page = try await profiles.following(
                of: viewerID,
                page: PageRequest(cursor: cursor, limit: FollowListPagination.pageSize)
            )
            for profile in page.items where seen.insert(profile.id).inserted {
                aggregated.append(profile)
            }
            cursor = page.nextCursor
        } while cursor != nil
        return aggregated
    }

    private func loadSuggestedPage(reset: Bool) async {
        guard let viewerID, showsSuggestedSection || reset else { return }
        if reset {
            suggestedProfiles = []
            suggestedNextCursor = nil
        }

        let followingIDs = Set(followingProfiles.map(\.id))

        do {
            let page = try await explore.discoverableProfiles(
                page: PageRequest(cursor: suggestedNextCursor, limit: Self.suggestedPageSize)
            )
            let filtered = filterSuggestedCandidates(
                page.items,
                viewerID: viewerID,
                excludingFollowingIDs: followingIDs
            )
            var seen = Set(suggestedProfiles.map(\.id))
            for profile in filtered where seen.insert(profile.id).inserted {
                suggestedProfiles.append(profile)
                detailCache.seed(profile)
            }
            suggestedNextCursor = page.nextCursor
            canLoadMoreSuggested = suggestedNextCursor != nil
        } catch {
            if reset {
                suggestedProfiles = []
            }
            canLoadMoreSuggested = false
        }
    }

    private func filterDiscoverableCandidates(_ profiles: [Profile], viewerID: ProfileID) -> [Profile] {
        profiles.filter { profile in
            profile.id != viewerID
                && !profile.isPrivate
                && !profile.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !FeedBlockedAuthorsFilter.shared.contains(profile.id)
        }
    }

    private func filterSuggestedCandidates(
        _ profiles: [Profile],
        viewerID: ProfileID,
        excludingFollowingIDs: Set<ProfileID>
    ) -> [Profile] {
        profiles.filter { profile in
            profile.id != viewerID
                && !excludingFollowingIDs.contains(profile.id)
                && !profile.isPrivate
                && !profile.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !FeedBlockedAuthorsFilter.shared.contains(profile.id)
        }
    }
}

private extension Array {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}