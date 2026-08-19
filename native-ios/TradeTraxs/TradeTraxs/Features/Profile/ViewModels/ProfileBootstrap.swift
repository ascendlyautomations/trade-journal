import Foundation

/// Coordinated Profile first-paint load — Stage 1 only (header + Follow).
///
/// Section payloads (trades / posts / clips / achievements / accounts) load lazily
/// when their tab activates via section ViewModels — one request per resource.
/// Conforms to ``ScreenBootstrap`` (canonical first-paint contract).
@MainActor
enum ProfileBootstrap: ScreenBootstrap {
    struct Context {
        var target: ProfileContentStore.Target
        var profiles: any ProfileRepository
        var trades: any TradeRepository
        var achievements: any AchievementRepository
        var feed: any FeedRepository
        var rooms: any RoomRepository
        var session: any SessionProviding
        var detailCache: DetailPresentationCache
        var force: Bool
    }

    static func load(_ context: Context) async -> ProfileState {
        var state = ProfileState()
        state.phase = .loading

        let userID = await context.session.currentUserID
        let viewerID = userID.map { ProfileID($0.rawValue) }

        let profileID: ProfileID
        switch context.target {
        case .currentUser:
            guard let viewerID else {
                state.phase = .failed
                state.errorMessage = UserFacingError.map(
                    AppError.domain(.permission(.notAuthenticated))
                ).message
                return state
            }
            profileID = viewerID
        case .profile(let id):
            profileID = id
        }

        state.profileID = profileID
        state.isOwner = viewerID == profileID

        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            return developmentState(profileID: profileID, isOwner: state.isOwner, viewerID: viewerID)
        }

        do {
            // Stage 1 — critical path for header + Follow (no section fan-out).
            async let profileTask = loadProfile(profileID, context: context)
            async let statsTask = loadStats(profileID, context: context)
            async let roomTask = loadOwnedRoom(profileID, context: context)
            async let followTask = loadFollowState(
                profileID: profileID,
                isOwner: state.isOwner,
                viewerID: viewerID,
                context: context
            )

            let loadedProfile = try await profileTask
            let loadedStats = try await statsTask
            let room = await roomTask
            let isFollowing = await followTask

            guard !Task.isCancelled else { return state }

            context.detailCache.seed(loadedProfile)
            context.detailCache.seed(stats: loadedStats)
            context.detailCache.seedOwnedTradeRoom(room, for: profileID)

            state.profile = loadedProfile
            state.stats = loadedStats
            state.ownedTradeRoom = room
            state.didResolveTradeRoom = true
            state.isFollowing = isFollowing
            // Section lists intentionally deferred — flags stay false until tab load.
            state.didLoadTrades = false
            state.didLoadPosts = false
            state.didLoadClips = false
            state.didLoadAchievements = false
            state.phase = .loaded
            state.didBootstrap = true
            state.errorMessage = nil
        } catch is CancellationError {
            // Keep prior snapshot.
        } catch {
            state.phase = state.profile == nil ? .failed : state.phase
            state.errorMessage = UserFacingError.map(
                error as? AppError ?? AppError.unknown(message: error.localizedDescription)
            ).message
        }

        return state
    }

    // MARK: - Private

    private static func loadProfile(
        _ profileID: ProfileID,
        context: Context
    ) async throws -> Profile {
        if !context.force, let cached = context.detailCache.profile(id: profileID) {
            return cached
        }
        return try await context.profiles.profile(id: profileID)
    }

    private static func loadStats(
        _ profileID: ProfileID,
        context: Context
    ) async throws -> ProfileStats {
        if !context.force, let cached = context.detailCache.stats(for: profileID) {
            return cached
        }
        return try await context.profiles.stats(for: profileID)
    }

    private static func loadOwnedRoom(
        _ profileID: ProfileID,
        context: Context
    ) async -> TradeRoom? {
        if !context.force, context.detailCache.hasResolvedOwnedTradeRoom(for: profileID) {
            return context.detailCache.ownedTradeRoom(for: profileID)
        }
        do {
            let page = try await context.rooms.rooms(for: profileID, page: PageRequest(limit: 1))
            return page.items.first
        } catch {
            return nil
        }
    }

    private static func loadFollowState(
        profileID: ProfileID,
        isOwner: Bool,
        viewerID: ProfileID?,
        context: Context
    ) async -> Bool {
        guard !isOwner, let viewerID else { return false }
        // Prefer per-edge cache — never treat a partial following-ID set as complete.
        if let edge = context.detailCache.viewerFollowEdge(for: profileID) {
            return edge
        }
        do {
            let follow = try await context.profiles.followState(from: viewerID, to: profileID)
            let isFollowing = follow == .following
            context.detailCache.setViewerFollows(profileID, isFollowing: isFollowing)
            return isFollowing
        } catch {
            return false
        }
    }

    private static func developmentState(
        profileID: ProfileID,
        isOwner: Bool,
        viewerID: ProfileID?
    ) -> ProfileState {
        let profile = FollowListFixtures.profile(id: profileID)
            ?? Profile(
                id: profileID,
                userID: UserID(profileID.rawValue),
                username: "tradetraxs",
                displayName: "TradeTraxs",
                bio: "Journal every trade. Improve every session.",
                avatar: nil,
                traderType: .futures,
                tradingStyle: "ICT",
                primaryMarket: "NQ",
                startedTradingAt: Calendar.current.date(byAdding: .month, value: -41, to: Date()),
                isPrivate: false,
                isCreator: true,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        let achievements = ProfileAchievementFixtures.samples(owner: profileID)
        let payoutTotal = ProfilePayoutTotals.sum(from: achievements)
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

        var state = ProfileState()
        state.phase = .loaded
        state.profileID = profileID
        state.profile = profile
        state.stats = stats
        state.isOwner = isOwner
        state.trades = ProfileTradeFixtures.samples(owner: profileID)
        state.accountNames = ProfileTradeFixtures.accountNames()
        state.accountNumbers = isOwner ? ProfileTradeFixtures.accountNumbers() : [:]
        state.accountModes = ProfileTradeFixtures.accountModes()
        state.accountSizes = ProfileTradeFixtures.accountSizes()
        state.posts = ProfilePostFixtures.samples(owner: profileID)
        state.clips = ProfileClipFixtures.samples(owner: profileID)
        state.achievements = achievements
        state.ownedTradeRoom = developmentTradeRoom(for: profileID)
        state.didResolveTradeRoom = true
        state.didLoadTrades = true
        state.didLoadPosts = true
        state.didLoadClips = true
        state.didLoadAchievements = true
        if !isOwner, let viewerID {
            let ids = Set(FollowListFixtures.following(owner: viewerID).map(\.id))
            state.isFollowing = ids.contains(profileID)
        }
        state.didBootstrap = true
        return state
    }

    private static func developmentTradeRoom(for profileID: ProfileID) -> TradeRoom? {
        let roomOwners: Set<String> = [
            "dev.follower.ada",
            "dev.following.ict",
            "dev.following.nq",
        ]
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
