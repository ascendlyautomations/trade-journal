import Foundation

/// Local Demo Mode repositories. Reads come from ``DemoGraph`` / ``DemoCanonicalDataset``.
/// Mutations never reach Supabase, guest RPCs, StoreKit, or broker APIs.
struct DemoFeedRepository: FeedRepository {
    func feed(
        scope: FeedScope,
        contentFilter: FeedContentFilter,
        page: PageRequest
    ) async throws -> FeedPageResult {
        _ = scope
        guard page.cursor == nil else {
            return FeedPageResult(items: [], nextCursor: nil, embeddedTrades: [])
        }
        let entries = DemoGraph.feedEntries(viewerID: DemoExperienceSupport.profileID)
            .filter { $0.matches(filter: contentFilter) }
        let trades = DemoCanonicalDataset.trades().filter { trade in
            entries.contains { $0.item.tradeID == trade.id }
        }
        return FeedPageResult(
            items: entries.map(\.item),
            nextCursor: nil,
            embeddedTrades: trades
        )
    }

    func post(id: PostID) async throws -> Post {
        guard let post = DemoGraph.post(id: id) else {
            throw AppError.domain(.notFound(entity: "post", id: id.rawValue))
        }
        return post
    }

    func posts(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        _ = page
        let items = profileID == DemoExperienceSupport.profileID || DemoGraph.profile(id: profileID) != nil
            ? DemoGraph.posts(owner: profileID)
            : []
        return CursorPage(items: items, nextCursor: nil)
    }

    func createPost(_ post: Post) async throws -> Post { throw DemoAuthRequired.error }
    func deletePost(id: PostID) async throws { throw DemoAuthRequired.error }

    func comments(for postID: PostID, page: PageRequest) async throws -> CursorPage<Comment> {
        _ = (postID, page)
        return CursorPage(items: [], nextCursor: nil)
    }

    func addComment(_ comment: Comment) async throws -> Comment { throw DemoAuthRequired.error }
    func setReaction(on item: FeedItem, kind: ReactionKind, isActive: Bool) async throws {
        throw DemoAuthRequired.error
    }

    func stories(for viewer: ProfileID) async throws -> [Story] {
        DemoGraph.stories(viewerID: viewer)
    }

    func createStory(userID: ProfileID, imageURL: String) async throws -> Story {
        _ = (userID, imageURL)
        throw DemoAuthRequired.error
    }

    func reel(id: ReelID) async throws -> ReelLoadResult {
        guard let reel = DemoGraph.clips().first(where: { $0.id == id }) else {
            throw AppError.domain(.notFound(entity: "reel", id: id.rawValue))
        }
        let trade = reel.linkedTradeID.flatMap { tradeID in
            DemoCanonicalDataset.trades().first { $0.id == tradeID }
        }
        return ReelLoadResult(reel: reel, embeddedTrade: trade)
    }

    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        _ = page
        return CursorPage(items: DemoGraph.clips(owner: profileID), nextCursor: nil)
    }

    func profileReels(for profileID: ProfileID) async throws -> ProfileReelsResult {
        let reels = DemoGraph.clips(owner: profileID)
        let trades = DemoCanonicalDataset.trades().filter { trade in
            reels.contains { $0.linkedTradeID == trade.id }
        }
        return ProfileReelsResult(reels: reels, embeddedTrades: trades)
    }

    func createReel(_ reel: Reel) async throws -> Reel { throw DemoAuthRequired.error }
}

struct DemoExploreRepository: ExploreRepository {
    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile> {
        _ = page
        return CursorPage(items: DemoGraph.profiles(), nextCursor: nil)
    }

    func socialCounts(for profileIDs: [ProfileID]) async throws -> ExploreSocialCounts {
        var followers: [ProfileID: Int] = [:]
        var following: [ProfileID: Int] = [:]
        for id in profileIDs {
            followers[id] = 48
            following[id] = 12
        }
        return ExploreSocialCounts(followers: followers, following: following)
    }

    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary] {
        _ = limit
        return [:]
    }

    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion] {
        _ = limit
        return [DemoExploreTradeRoom.discoverySuggestion(joined: true)]
    }

    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] {
        _ = limit
        let room = DemoExploreTradeRoom.room()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty
            || room.name.localizedCaseInsensitiveContains(trimmed)
            || room.slug.localizedCaseInsensitiveContains(trimmed)
        else { return [] }
        return [DemoExploreTradeRoom.discoverySuggestion(joined: true)]
    }

    func tradeRoomsHomeBootstrap(
        scope: TradeRoomDiscoveryScope,
        limit: Int,
        suggestedCursor: String?,
        popularCursor: String?
    ) async throws -> TradeRoomsHomeBootstrap {
        _ = (limit, suggestedCursor, popularCursor)
        return DemoExploreTradeRoom.homeBootstrap(
            viewerID: DemoExperienceSupport.profileID,
            scope: scope
        )
    }
}

struct DemoHomeRepository: HomeRepository {
    func dashboard(for profileID: ProfileID) async throws -> HomeDashboard {
        let interval = DateIntervalValue(
            start: Date().addingTimeInterval(-86_400 * 92),
            end: Date()
        )
        return HomeDashboard(
            summary: try await performance(for: profileID, interval: interval),
            widgets: [
                HomeWidget(kind: .dailyPnL, isEnabled: true),
                HomeWidget(kind: .calendar, isEnabled: true),
            ],
            insights: [],
            shortcutDestinations: [],
            refreshedAt: Date()
        )
    }

    func performance(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> PerformanceSummary {
        _ = profileID
        let trades = DemoCanonicalDataset.trades().filter {
            $0.entryAt >= interval.start && $0.entryAt <= interval.end
        }
        let pnls = trades.compactMap(\.realizedPnL?.amount)
        let total = pnls.reduce(Decimal(0), +)
        let wins = pnls.filter { $0 > 0 }.count
        let losses = pnls.filter { $0 < 0 }.count
        let count = max(trades.count, 1)
        let average = total / Decimal(count)
        let rate = trades.isEmpty ? Decimal(0) : Decimal(wins) / Decimal(count)
        let best = trades.max { ($0.realizedPnL?.amount ?? 0) < ($1.realizedPnL?.amount ?? 0) }
        let worst = trades.min { ($0.realizedPnL?.amount ?? 0) < ($1.realizedPnL?.amount ?? 0) }
        return PerformanceSummary(
            interval: interval,
            statistics: TradeStatistics(
                tradeCount: trades.count,
                winCount: wins,
                lossCount: losses,
                totalPnL: Money(amount: total),
                averagePnL: Money(amount: average),
                averageRiskReward: nil,
                winRate: rate
            ),
            bestTradeID: best?.id,
            worstTradeID: worst?.id,
            currentStreakDays: 0
        )
    }
}

struct DemoAIRepository: AIRepository {
    func analyzeTrade(_ request: TradeAIAnalyzeRequest) async throws -> TradeAIAnalyzeResponse {
        _ = request
        return TradeAIAnalyzeResponse(
            reply: "Demo Mode keeps this review on device. Create a TradeTraxs account for live Trade AI."
        )
    }

    func loadConversation(tradeID: TradeID) async throws -> [TradeAIMessage] {
        _ = tradeID
        return []
    }

    func persistMessages(_ messages: [TradeAIMessage], tradeID: TradeID) async throws {
        _ = (messages, tradeID)
    }

    func explainPsychologyCoach(_ request: PsychologyCoachAIRequest) async throws -> PsychologyCoachAIResponse {
        _ = request
        return PsychologyCoachAIResponse(
            reply: "Demo Mode explains this check-in from the sample journal. A TradeTraxs account unlocks the live coach."
        )
    }

    func extractScreenshotTrades(_ request: ScreenshotAIExtractRequest) async throws -> ScreenshotAIExtractResponse {
        _ = request
        return ScreenshotAIExtractResponse(
            extraction: nil,
            error: "Screenshot import needs a TradeTraxs account."
        )
    }
}

struct DemoBillingRepository: BillingRepository {
    func status(for profileID: ProfileID) async throws -> BillingStatus {
        demoStatus(profileID)
    }

    func subscription(for profileID: ProfileID) async throws -> Subscription? {
        _ = profileID
        return nil
    }

    func refreshEntitlements(for profileID: ProfileID) async throws -> BillingStatus {
        demoStatus(profileID)
    }

    private func demoStatus(_ profileID: ProfileID) -> BillingStatus {
        BillingStatus(
            profileID: profileID,
            plan: .free,
            lifecycle: .none,
            isProEntitled: false,
            entitlementSource: .none,
            serverTraxProActive: nil
        )
    }
}

struct DemoReferralRepository: ReferralRepository {
    func referral(for profileID: ProfileID) async throws -> Referral? {
        _ = profileID
        return nil
    }

    func apply(code: String, invitee: ProfileID) async throws -> Referral {
        _ = (code, invitee)
        throw DemoAuthRequired.error
    }
}

struct DemoUserSubmissionRepository: UserSubmissionRepository {
    func submitSupportTicket(_ submission: SupportTicketSubmission) async throws {
        _ = submission
        throw UserSubmissionError.validation("Create a TradeTraxs account to contact support.")
    }

    func submitFeedback(_ submission: FeedbackSubmission) async throws {
        _ = submission
        throw UserSubmissionError.validation("Create a TradeTraxs account to send feedback.")
    }

    func submitBugReport(_ submission: BugReportSubmission) async throws {
        _ = submission
        throw UserSubmissionError.validation("Create a TradeTraxs account to send a bug report.")
    }
}

struct DemoStoreKitSubscriptionService: StoreKitSubscriptionServicing {
    func syncVerifiedTransactionsToServer() async throws {}
    func startTransactionListenerIfNeeded() async {}
    func loadProducts() async throws -> [StoreKitTraxProProduct] { [] }
    func purchase(productID: String, appAccountToken: UUID?) async -> StoreKitPurchaseOutcome {
        _ = (productID, appAccountToken)
        return .failed("Subscriptions need a TradeTraxs account.")
    }
    func restorePurchases() async throws -> Bool { false }
    func presentOfferCodeRedemption() async throws {}
}
