import Foundation
import Observation

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
    var searchText = ""
    var groupName = ""

    private let messages: any MessageRepository
    private let search: any SearchRepository
    private let profiles: any ProfileRepository
    private let explore: any ExploreRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let inboxStore: MessagesInboxStore
    private let creationCoordinator: ConversationCreationCoordinator

    private var viewerID: ProfileID?
    private var searchTask: Task<Void, Never>?
    private var suggestions: [Profile] = []
    private var searchGeneration: UInt64 = 0
    private var openingProfileID: ProfileID?
    private var isCreatingGroup = false

    init(
        messages: any MessageRepository,
        search: any SearchRepository,
        profiles: any ProfileRepository,
        explore: any ExploreRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        inboxStore: MessagesInboxStore? = nil,
        creationCoordinator: ConversationCreationCoordinator? = nil
    ) {
        self.messages = messages
        self.search = search
        self.profiles = profiles
        self.explore = explore
        self.session = session
        self.detailCache = detailCache
        self.inboxStore = inboxStore ?? MessagesInboxStore.shared
        self.creationCoordinator = creationCoordinator ?? .shared
    }

    var normalizedQuery: String {
        SearchQueryNormalization.normalizePeopleQuery(searchText)
    }

    var isSearching: Bool {
        !normalizedQuery.isEmpty
    }

    var visibleResults: [Profile] {
        if normalizedQuery.isEmpty { return suggestions }
        return results
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
        phase = .idle
    }

    func backToChooser() {
        searchTask?.cancel()
        mode = .chooser
        searchText = ""
        results = []
        selectedGroupMembers = []
        groupName = ""
        phase = .idle
        openingProfileID = nil
        isCreatingGroup = false
    }

    func prepare() async {
        if let raw = await session.currentUserID?.rawValue {
            viewerID = ProfileID(raw)
        }
        if let viewerID, MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) {
            suggestions = FollowListFixtures.following(owner: viewerID)
            for profile in suggestions { detailCache.seed(profile) }
            return
        }
        if let viewerID, let following = detailCache.following(for: viewerID), !following.isEmpty {
            suggestions = following.filter { $0.id != viewerID }
            return
        }
        guard let viewerID else { return }
        if let page = try? await explore.discoverableProfiles(page: PageRequest(limit: 48)) {
            suggestions = page.items.filter { $0.id != viewerID && !$0.isPrivate }
            for profile in suggestions { detailCache.seed(profile) }
        }
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
        searchGeneration &+= 1
        results = []
        searchText = ""
        selectedGroupMembers = []
        groupName = ""
        mode = .chooser
        phase = .idle
        openingProfileID = nil
        isCreatingGroup = false
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

    /// Opens an existing 1:1 conversation or creates one — never duplicates.
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
            return nil
        } catch {
            phase = .failed(MessagesInboxSupport.message(for: error))
            ExperienceHaptics.play(.warning)
            return nil
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
