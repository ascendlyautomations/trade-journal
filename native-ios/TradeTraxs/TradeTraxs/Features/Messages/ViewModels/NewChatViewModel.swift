import Foundation
import Observation

@Observable
@MainActor
final class NewChatViewModel {
    enum Phase: Equatable {
        case idle
        case searching
        case opening
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var results: [Profile] = []
    var searchText = ""

    private let messages: any MessageRepository
    private let search: any SearchRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let inboxStore: MessagesInboxStore

    private var viewerID: ProfileID?
    private var searchTask: Task<Void, Never>?
    private var suggestions: [Profile] = []

    init(
        messages: any MessageRepository,
        search: any SearchRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        inboxStore: MessagesInboxStore? = nil
    ) {
        self.messages = messages
        self.search = search
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.inboxStore = inboxStore ?? MessagesInboxStore.shared
    }

    var visibleResults: [Profile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return suggestions }
        return results
    }

    var prompt: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Search people"
            : "No matching people"
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
        if let viewerID, let following = detailCache.following(for: viewerID) {
            suggestions = following
        }
    }

    func searchChanged() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            phase = .idle
            return
        }

        if let viewerID, MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) {
            let lowered = query.lowercased()
            results = (FollowListFixtures.followers(owner: viewerID) + FollowListFixtures.following(owner: viewerID))
                .uniqued(by: \.id)
                .filter {
                    $0.displayName.lowercased().contains(lowered)
                        || $0.username.lowercased().contains(lowered)
                }
            phase = .idle
            return
        }

        phase = .searching
        searchTask = Task {
            // Debounce keystrokes — picker search is the only network search surface.
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            do {
                let page = try await search.search(
                    query: query,
                    kinds: [.profile],
                    page: PageRequest(limit: 24)
                )
                guard !Task.isCancelled else { return }
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
                // Preserve search-result order; synthesize minimal profiles when batch misses.
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
                results = profiles
                phase = .idle
            } catch {
                phase = .failed(MessagesInboxSupport.message(for: error))
            }
        }
    }

    /// Opens an existing 1:1 conversation or creates one — never duplicates.
    func select(_ profile: Profile) async -> Conversation? {
        guard let viewerID else { return nil }
        ExperienceHaptics.play(.selection)
        phase = .opening
        defer { phase = .idle }

        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
            || MessagesInboxSupport.isLocalDevelopmentProfile(profile.id)
        {
            let participants = Set([viewerID, profile.id])
            if let existing = inboxStore.conversations.first(where: {
                Set($0.participantProfileIDs) == participants
            }) {
                return existing
            }
            let created = Conversation(
                id: ConversationID("dev-dm-\(viewerID.rawValue)-\(profile.id.rawValue)"),
                participantProfileIDs: [viewerID, profile.id],
                title: profile.displayName,
                peerUsername: profile.username,
                avatar: profile.avatar,
                isGroup: false,
                isPinned: false,
                lastMessagePreview: nil,
                lastMessageAt: nil,
                unreadCount: 0,
                isMuted: false,
                updatedAt: .now
            )
            detailCache.seed(profile)
            inboxStore.upsertConversation(created)
            return created
        }

        do {
            // Repository mirrors web `ensureDmConversation` (find via participants, else create).
            let created = try await messages.createConversation(participantIDs: [viewerID, profile.id])
            detailCache.seed(profile)
            inboxStore.upsertConversation(created)
            return created
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
