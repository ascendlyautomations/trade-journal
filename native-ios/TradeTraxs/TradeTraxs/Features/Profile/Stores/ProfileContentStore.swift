import Foundation
import Observation
import SwiftUI
import UIKit

/// Unified Profile header/session content for the current user or any other profile.
///
/// Same load path as the owner Profile — repositories + image pipeline + ``DetailPresentationCache``.
/// Ownership only changes the action row.
@Observable
@MainActor
final class ProfileContentStore {
    enum Phase: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed
    }

    enum Target: Hashable, Sendable {
        /// Resolve the authenticated user from the session.
        case currentUser
        /// Explicit profile (Followers / Feed / Detail / Search / …).
        case profile(ProfileID)
    }

    let target: Target

    private(set) var phase: Phase = .idle
    private(set) var profile: Profile?
    private(set) var stats: ProfileStats?
    private(set) var avatarImage: Image?
    private(set) var errorMessage: String?
    private(set) var isOwner = false
    private(set) var isFollowing = false
    private(set) var isRequested = false
    private(set) var followsYou = false
    private(set) var canViewTrades = true
    private(set) var resolvedProfileID: ProfileID?
    /// First owned Trade Room when present (hidden in UI when nil after resolve).
    private(set) var ownedTradeRoom: TradeRoom?
    private(set) var didResolveTradeRoom = false
    private(set) var activeStories: [Story] = []

    private let profiles: any ProfileRepository
    private let rooms: any RoomRepository
    private let session: any SessionProviding
    private let imagePipeline: any ImagePipeline
    private let detailCache: DetailPresentationCache

    private var loadTask: Task<Void, Never>?
    private var loadedAvatarKey: String?
    private var followInFlight = false
    private var viewerID: ProfileID?

    init(
        target: Target,
        profiles: any ProfileRepository,
        rooms: any RoomRepository,
        session: any SessionProviding,
        imagePipeline: any ImagePipeline,
        detailCache: DetailPresentationCache
    ) {
        self.target = target
        self.profiles = profiles
        self.rooms = rooms
        self.session = session
        self.imagePipeline = imagePipeline
        self.detailCache = detailCache
    }

    var initials: String {
        guard let profile else { return "" }
        return ProfileDisplay.initials(displayName: profile.displayName, username: profile.username)
    }

    var hasTradeRoom: Bool { ownedTradeRoom != nil }

    /// Newest active story for avatar ring — from bootstrap, not a follow-up fetch.
    var activeStory: Story? {
        StoryBootstrapMapping.newestActive(activeStories)
    }

    /// Web `canShowVisitorRoomCta` — owned room + `show_on_profile` + viewable profile content.
    /// Profile does not check membership; visitors always get “View Trade Room” when shown.
    var canShowVisitorTradeRoomCTA: Bool {
        guard !isOwner, let profile, let room = ownedTradeRoom else { return false }
        let canViewTrades = !profile.isPrivate || isFollowing
        guard canViewTrades, room.showsOnProfile else { return false }
        let slug = room.slug.trimmingCharacters(in: .whitespacesAndNewlines)
        if !slug.isEmpty { return true }
        return !room.id.rawValue.isEmpty
    }

    /// When true, ``ProfileScreenViewModel`` owns network — ``loadIfNeeded`` is a no-op.
    private(set) var isScreenOwned = false

    /// Applies header fields from the screen bootstrap. Does not hit the network.
    func applyBootstrap(_ state: ProfileState) {
        isScreenOwned = true
        resolvedProfileID = state.profileID
        isOwner = state.isOwner
        isFollowing = state.isFollowing
        isRequested = state.isRequested
        followsYou = state.followsYou
        canViewTrades = state.canViewTrades
        profile = state.profile
        stats = state.stats
        ownedTradeRoom = state.ownedTradeRoom
        didResolveTradeRoom = state.didResolveTradeRoom
        applyActiveStories(from: state.activeStories, isOwner: state.isOwner)
        errorMessage = state.errorMessage
        // Follow must work as soon as Stage 1 publishes — capture viewer for toggle.
        Task { [weak self] in
            guard let self else { return }
            if self.viewerID == nil {
                let userID = await self.session.currentUserID
                self.viewerID = userID.map { ProfileID($0.rawValue) }
            }
        }
        switch state.phase {
        case .idle: phase = .idle
        case .loading: phase = profile == nil ? .loading : phase
        case .loaded: phase = .loaded
        case .failed: phase = .failed
        }
        if let profile {
            Task { await loadAvatarIfNeeded(for: profile, force: false) }
        }
    }

    func loadIfNeeded(force: Bool = false) {
        // Screen-owned Profile uses ``ProfileBootstrap`` — keep this path for unit tests
        // and any non-screen callers.
        if isScreenOwned, !force { return }
        if loadTask != nil, !force { return }
        if !force, phase == .loaded, profile != nil {
            if !didResolveTradeRoom, let profileID = resolvedProfileID {
                loadTask = Task { [weak self] in
                    await self?.resolveOwnedTradeRoom(for: profileID, force: false)
                    self?.loadTask = nil
                }
            }
            return
        }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoad(force: force)
        }
    }

    func refresh() {
        loadIfNeeded(force: true)
    }

    func toggleFollow() async {
        guard !isOwner, let profileID = resolvedProfileID, !followInFlight else { return }
        // Resolve viewer lazily — Stage-1 bootstrap historically never set viewerID.
        if viewerID == nil {
            let userID = await session.currentUserID
            viewerID = userID.map { ProfileID($0.rawValue) }
        }
        guard let viewerID else { return }
        followInFlight = true
        defer { followInFlight = false }

        let previous = isFollowing
        let next = !previous
        isFollowing = next
        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewerID,
            target: profileID,
            isFollowing: next
        )
        if let patched = detailCache.stats(for: profileID) {
            stats = patched
        }
        ExperienceHaptics.play(.selection)

        if profileID.rawValue.hasPrefix("dev.") {
            return
        }

        do {
            if next {
                try await profiles.follow(from: viewerID, to: profileID)
            } else {
                try await profiles.unfollow(from: viewerID, to: profileID)
            }
        } catch {
            isFollowing = previous
            FollowMutationCoordinator.shared.applyEdgeChange(
                viewer: viewerID,
                target: profileID,
                isFollowing: previous
            )
            if let patched = detailCache.stats(for: profileID) {
                stats = patched
            }
            ExperienceHaptics.play(.warning)
        }
    }

    /// External FollowMutationCoordinator patch — keeps header button + counts live.
    func applyExternalFollowState(isFollowing: Bool, stats: ProfileStats?) {
        if !isOwner {
            self.isFollowing = isFollowing
        }
        if let stats {
            self.stats = stats
        }
    }

    func applyStoryCreated(_ story: Story) {
        guard isOwner, story.authorProfileID == resolvedProfileID else { return }
        detailCache.seed(story)
        var merged = activeStories.filter { $0.id != story.id }
        merged.append(story)
        activeStories = ActiveStorySemantics.filterActive(merged)
        if let profileID = resolvedProfileID {
            ViewerActiveStoryStore.shared.applyStoryCreated(story, viewerID: profileID)
        }
    }

    func applyStoryDeleted(_ storyID: StoryID) {
        activeStories.removeAll { $0.id == storyID }
        detailCache.removeStory(id: storyID)
        ViewerActiveStoryStore.shared.applyStoryDeleted(storyID)
    }

    func reconcileExpiredStories(now: Date = Date()) {
        let filtered = ActiveStorySemantics.filterActive(activeStories, now: now)
        if filtered.count != activeStories.count {
            activeStories = filtered
        }
    }

    // MARK: - Private

    private func applyActiveStories(from incoming: [Story], isOwner: Bool) {
        let activeIncoming = ActiveStorySemantics.filterActive(incoming)
        if !activeIncoming.isEmpty {
            activeStories = activeIncoming
            for story in activeIncoming {
                detailCache.seed(story)
            }
            if isOwner, let profileID = resolvedProfileID {
                ViewerActiveStoryStore.shared.sync(viewerID: profileID, stories: activeIncoming)
            }
            return
        }

        // Empty RPC payload — keep optimistic owner story until server confirms deletion.
        if isOwner {
            let retained = ActiveStorySemantics.filterActive(activeStories)
            if !retained.isEmpty { return }
        }
        activeStories = []
    }

    private func performLoad(force: Bool) async {
        phase = profile == nil ? .loading : phase
        errorMessage = nil

        let userID = await session.currentUserID
        viewerID = userID.map { ProfileID($0.rawValue) }

        let profileID: ProfileID
        switch target {
        case .currentUser:
            guard let viewerID else {
                phase = .failed
                errorMessage = UserFacingError.map(
                    AppError.domain(.permission(.notAuthenticated))
                ).message
                loadTask = nil
                return
            }
            profileID = viewerID
        case .profile(let id):
            profileID = id
        }

        resolvedProfileID = profileID
        isOwner = viewerID == profileID

        if !force,
           let cachedProfile = detailCache.profile(id: profileID),
           let cachedStats = detailCache.stats(for: profileID),
           cachedStats.hasLoadedHeaderMetrics
        {
            profile = cachedProfile
            stats = cachedStats
            phase = .loaded
            await loadAvatarIfNeeded(for: cachedProfile, force: false)
            await resolveFollowState(for: profileID)
            await resolveOwnedTradeRoom(for: profileID, force: false)
            loadTask = nil
            return
        }

        if let local = Self.developmentFixture(for: profileID) {
            profile = local.profile
            stats = local.stats
            detailCache.seed(local.profile)
            detailCache.seed(stats: local.stats)
            phase = .loaded
            await loadAvatarIfNeeded(for: local.profile, force: force)
            await resolveFollowState(for: profileID)
            await resolveOwnedTradeRoom(for: profileID, force: force)
            loadTask = nil
            return
        }

        do {
            async let profileTask = profiles.profile(id: profileID)
            async let statsTask = profiles.stats(for: profileID)
            let (loadedProfile, loadedStats) = try await (profileTask, statsTask)
            guard !Task.isCancelled else { return }

            profile = loadedProfile
            stats = loadedStats
            detailCache.seed(loadedProfile)
            detailCache.seed(stats: loadedStats)
            phase = .loaded
            await loadAvatarIfNeeded(for: loadedProfile, force: force)
            await resolveFollowState(for: profileID)
            await resolveOwnedTradeRoom(for: profileID, force: force)
        } catch is CancellationError {
            // Keep prior content.
        } catch {
            if profile == nil {
                phase = .failed
            }
            errorMessage = UserFacingError.map(
                error as? AppError ?? AppError.unknown(message: error.localizedDescription)
            ).message
        }
        loadTask = nil
    }

    private func resolveFollowState(for profileID: ProfileID) async {
        guard !isOwner, let viewerID else {
            isFollowing = false
            return
        }
        if let cached = detailCache.viewerFollowEdge(for: profileID) {
            isFollowing = cached
            return
        }
        if let cached = detailCache.viewerFollowingIDs() {
            // Complete following list only (seeded from Follow list) — safe to consult.
            isFollowing = cached.contains(profileID)
            return
        }
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID)
            || ProfileSectionSupport.isLocalDevelopmentProfile(viewerID)
        {
            let ids = Set(FollowListFixtures.following(owner: viewerID).map(\.id))
            detailCache.seedViewerFollowingIDs(ids)
            isFollowing = ids.contains(profileID)
            return
        }
        do {
            let state = try await profiles.followState(from: viewerID, to: profileID)
            isFollowing = state == .following
            detailCache.setViewerFollows(profileID, isFollowing: isFollowing)
        } catch {
            isFollowing = false
        }
    }

    private func resolveOwnedTradeRoom(for profileID: ProfileID, force: Bool) async {
        if !force, detailCache.hasResolvedOwnedTradeRoom(for: profileID) {
            let cached = detailCache.ownedTradeRoom(for: profileID)
            ownedTradeRoom = cached
            // A cached miss may be from the old `owner_id` filter — refetch once so
            // web-parity `owner_user_id` can resolve an owned room without a hard refresh.
            if cached != nil {
                didResolveTradeRoom = true
                return
            }
        }

        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            let room = Self.developmentTradeRoom(for: profileID)
            ownedTradeRoom = room
            detailCache.seedOwnedTradeRoom(room, for: profileID)
            didResolveTradeRoom = true
            return
        }

        do {
            let page = try await rooms.rooms(for: profileID, page: PageRequest(limit: 1))
            let room = page.items.first
            ownedTradeRoom = room
            detailCache.seedOwnedTradeRoom(room, for: profileID)
            didResolveTradeRoom = true
        } catch {
            ownedTradeRoom = nil
            didResolveTradeRoom = true
            detailCache.seedOwnedTradeRoom(nil, for: profileID)
        }
    }

    private func loadAvatarIfNeeded(for profile: Profile, force: Bool) async {
        guard let reference = profile.avatar else {
            avatarImage = nil
            loadedAvatarKey = nil
            return
        }
        if !force, loadedAvatarKey == reference.id, avatarImage != nil {
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 512
                )
            )
            guard !Task.isCancelled else { return }
            guard let uiImage = UIImage(data: data) else {
                avatarImage = nil
                loadedAvatarKey = nil
                return
            }
            avatarImage = Image(uiImage: uiImage)
            loadedAvatarKey = reference.id
        } catch {
            avatarImage = nil
            loadedAvatarKey = nil
        }
    }

    private static func developmentFixture(
        for profileID: ProfileID
    ) -> (profile: Profile, stats: ProfileStats)? {
        guard ProfileSectionSupport.isLocalDevelopmentProfile(profileID) else { return nil }
        let profile = FollowListFixtures.profile(id: profileID) ?? developmentSessionProfile(id: profileID)
        // Web overview `overviewPayoutTotal` = `sumPayoutAchievementTotals`.
        let payoutTotal = ProfilePayoutTotals.sum(
            from: ProfileAchievementFixtures.samples(owner: profileID)
        )
        let stats = ProfileStats(
            profileID: profileID,
            followerCount: 128,
            followingCount: 42,
            postCount: 18,
            tradeCount: 31,
            publicTradeCount: 31,
            winRate: Decimal(string: "0.58"),
            profitFactor: Decimal(string: "1.85"),
            netPnL: Decimal(string: "12450"),
            averageRR: Decimal(string: "2.1"),
            payoutTotal: payoutTotal,
            expectancy: nil
        )
        return (profile, stats)
    }

    /// Session-owner fallback when `dev.*` is not in FollowList fixtures.
    private static func developmentSessionProfile(id: ProfileID) -> Profile {
        let started = Calendar.current.date(byAdding: .month, value: -41, to: Date())
        return Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: "tradetraxs",
            displayName: "TradeTraxs",
            bio: "Journal every trade. Improve every session.",
            avatar: nil,
            traderType: .futures,
            tradingStyle: "ICT",
            primaryMarket: "NQ",
            startedTradingAt: started,
            isPrivate: false,
            isCreator: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// Dev fixtures: current user + select public profiles own a Trade Room.
    private static func developmentTradeRoom(for profileID: ProfileID) -> TradeRoom? {
        let roomOwners: Set<String> = [
            "dev.follower.ada",
            "dev.following.ict",
            "dev.following.nq",
        ]
        // Session owner (`dev.*` not in follow-list fixtures) also gets a room for View CTA.
        let isListedOwner = roomOwners.contains(profileID.rawValue)
        let isSessionOwner = FollowListFixtures.profile(id: profileID) == nil
        guard isListedOwner || isSessionOwner else { return nil }
        return TradeRoom(
            id: RoomID("dev-room-\(profileID.rawValue)"),
            ownerProfileID: profileID,
            name: "\(profileID.rawValue.hasPrefix("dev.follower.ada") ? "Ada" : "Trade") Room",
            slug: "room-\(profileID.rawValue)",
            description: "Public trade room",
            image: nil,
            memberCount: 128,
            showsOnProfile: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
