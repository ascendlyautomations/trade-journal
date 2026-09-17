import Foundation

nonisolated enum DemoAuthRequired {
    /// Same surface as ``AppError/domain(_:)`` `.permission(.notAuthenticated)` — safe from any executor.
    static let error: AppError = .authentication(.sessionMissing)
}

/// In-memory trade journal for Explore Mode — reads from ``DemoCanonicalDataset``.
nonisolated final class DemoTradeRepository: TradeRepository, @unchecked Sendable {
    private let ownerID: ProfileID
    private var trades: [Trade]
    private let accounts: [TradingAccount]

    init(
        ownerID: ProfileID = DemoExperienceSupport.profileID,
        trades: [Trade] = DemoCanonicalDataset.trades(),
        accounts: [TradingAccount] = DemoCanonicalDataset.accounts()
    ) {
        self.ownerID = ownerID
        self.trades = trades
        self.accounts = accounts
    }

    func trade(id: TradeID) async throws -> Trade {
        guard let trade = trades.first(where: { $0.id == id }) else {
            throw AppError.domain(.notFound(entity: "trade", id: id.rawValue))
        }
        return trade
    }

    func trades(ids: [TradeID]) async throws -> [Trade] {
        let wanted = Set(ids)
        return trades.filter { wanted.contains($0.id) }
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        guard profileID == ownerID else {
            return CursorPage(items: [], nextCursor: nil)
        }
        var list = trades
        if let accountID {
            list = list.filter { $0.accountID == accountID }
        }
        if publicOnly {
            list = list.filter { $0.visibility == .public }
        }
        list.sort { $0.entryAt > $1.entryAt }
        return paginate(list, page: page)
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        entryFrom: Date,
        entryTo: Date,
        limit: Int
    ) async throws -> [Trade] {
        guard profileID == ownerID else { return [] }
        var list = trades.filter { $0.entryAt >= entryFrom && $0.entryAt <= entryTo }
        if let accountID {
            list = list.filter { $0.accountID == accountID }
        }
        list.sort { $0.entryAt > $1.entryAt }
        return Array(list.prefix(max(1, limit)))
    }

    func tradeHistory(
        ownedBy profileID: ProfileID,
        query: TradeHistoryQuery,
        page: PageRequest
    ) async throws -> CursorPage<Trade> {
        guard profileID == ownerID else {
            return CursorPage(items: [], nextCursor: nil)
        }
        var list = trades
        if case .account(let accountID) = query.filters.account {
            list = list.filter { $0.accountID == accountID }
        }
        switch query.filters.visibility {
        case .public:
            list = list.filter { $0.visibility == .public }
        case .private:
            list = list.filter { $0.visibility == .private }
        case .any:
            break
        }
        switch query.filters.direction {
        case .long:
            list = list.filter { $0.side == .long }
        case .short:
            list = list.filter { $0.side == .short }
        case .any:
            break
        }
        list.sort { $0.entryAt > $1.entryAt }
        return paginate(list, page: page)
    }

    func statistics(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> TradeStatistics {
        guard profileID == ownerID else {
            return TradeStatistics(
                tradeCount: 0,
                winCount: 0,
                lossCount: 0,
                totalPnL: Money(amount: 0),
                averagePnL: Money(amount: 0),
                averageRiskReward: nil,
                winRate: 0
            )
        }
        let inInterval = trades.filter {
            $0.entryAt >= interval.start && $0.entryAt <= interval.end
        }
        let wins = inInterval.filter { ($0.realizedPnL?.amount ?? 0) > 0 }.count
        let losses = inInterval.filter { ($0.realizedPnL?.amount ?? 0) < 0 }.count
        let total = inInterval.reduce(Decimal(0)) { $0 + ($1.realizedPnL?.amount ?? 0) }
        let count = inInterval.count
        let average = count > 0 ? total / Decimal(count) : 0
        let winRate = count > 0 ? Decimal(wins) / Decimal(count) : 0
        return TradeStatistics(
            tradeCount: count,
            winCount: wins,
            lossCount: losses,
            totalPnL: Money(amount: total),
            averagePnL: Money(amount: average),
            averageRiskReward: nil,
            winRate: winRate
        )
    }

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] {
        guard profileID == ownerID else { return [] }
        return accounts
    }

    func images(for tradeID: TradeID) async throws -> [TradeImage] {
        let trade = try await trade(id: tradeID)
        guard let url = trade.thumbnail?.id else { return [] }
        return [
            TradeImage(
                id: TradeImageID(url),
                tradeID: tradeID,
                media: MediaReference(id: url, kind: .image, altText: nil),
                sortOrder: 0
            ),
        ]
    }

    func notes(for tradeID: TradeID) async throws -> [TradeNote] {
        let trade = try await trade(id: tradeID)
        guard let preview = trade.notePreview, !preview.isEmpty else { return [] }
        return [
            TradeNote(
                id: TradeNoteID(tradeID.rawValue),
                tradeID: tradeID,
                body: preview,
                createdAt: trade.createdAt,
                updatedAt: trade.updatedAt
            ),
        ]
    }

    func payoutEntries(for accountID: TradingAccountID) async throws -> [AccountPayoutEntry] {
        DemoCanonicalDataset.payoutEntries(for: accountID)
    }

    func payoutEntries(for accountIDs: [TradingAccountID]) async throws -> [AccountPayoutEntry] {
        accountIDs.flatMap { DemoCanonicalDataset.payoutEntries(for: $0) }
    }

    func profileAccountInsights(for profileID: ProfileID) async throws -> [ProfileAccountInsight] {
        guard profileID == ownerID else { return [] }
        return accounts.compactMap { account in
            let payouts = DemoCanonicalDataset.payoutEntries(for: account.id)
            let total = payouts.reduce(Decimal(0)) { $0 + $1.amount.amount }
            return ProfileAccountInsight(
                id: account.id,
                name: account.name,
                category: account.category,
                mode: account.mode,
                customStatus: nil,
                payoutTotal: Money(amount: total),
                payouts: payouts
            )
        }
    }

    func save(_ draft: TradeDraft) async throws -> Trade { throw DemoAuthRequired.error }
    func update(_ trade: Trade) async throws -> Trade { throw DemoAuthRequired.error }
    func delete(id: TradeID) async throws { throw DemoAuthRequired.error }
    func createAccount(ownerID: ProfileID, draft: TradingAccountDraft) async throws -> TradingAccount {
        throw DemoAuthRequired.error
    }
    func updateAccount(id: TradingAccountID, ownerID: ProfileID, draft: TradingAccountDraft) async throws -> TradingAccount {
        throw DemoAuthRequired.error
    }
    func setAccountActive(id: TradingAccountID, isActive: Bool) async throws { throw DemoAuthRequired.error }
    func updateAccountNote(id: TradingAccountID, note: String?) async throws { throw DemoAuthRequired.error }
    func updateAccountInsightsSettings(
        id: TradingAccountID,
        ownerID: ProfileID,
        showInAccountDropdowns: Bool,
        customPublicStatus: String?
    ) async throws -> TradingAccount {
        throw DemoAuthRequired.error
    }
    func createPayoutEntry(
        ownerID: ProfileID,
        accountID: TradingAccountID,
        draft: AccountPayoutEntryDraft
    ) async throws -> AccountPayoutEntry {
        throw DemoAuthRequired.error
    }
    func updatePayoutEntry(id: AccountPayoutEntryID, draft: AccountPayoutEntryDraft) async throws -> AccountPayoutEntry {
        throw DemoAuthRequired.error
    }
    func deletePayoutEntry(id: AccountPayoutEntryID) async throws { throw DemoAuthRequired.error }
    func payoutCycleHistory(for accountID: TradingAccountID) async throws -> [AccountPayoutCycle] { [] }
    func payoutCycleHistory(for accountIDs: [TradingAccountID]) async throws -> [AccountPayoutCycle] { [] }
    func recordAccountPayout(
        accountID: TradingAccountID,
        input: RecordAccountPayoutInput
    ) async throws -> RecordAccountPayoutResult {
        throw DemoAuthRequired.error
    }
    func importCSVTrades(_ drafts: [TradeDraft], isInitialImport: Bool) async throws -> Int {
        throw DemoAuthRequired.error
    }

    private func paginate(_ list: [Trade], page: PageRequest) -> CursorPage<Trade> {
        let limit = max(1, page.limit)
        let startIndex: Int
        if let cursor = page.cursor, let offset = Int(cursor) {
            startIndex = min(offset, list.count)
        } else {
            startIndex = 0
        }
        let end = min(startIndex + limit, list.count)
        let slice = startIndex < end ? Array(list[startIndex..<end]) : []
        let next: String? = end < list.count ? String(end) : nil
        return CursorPage(items: slice, nextCursor: next)
    }
}

/// Profile + social reads for the demo trader; writes require authentication.
nonisolated struct DemoProfileRepository: ProfileRepository {
    private let ownerID: ProfileID

    init(ownerID: ProfileID = DemoExperienceSupport.profileID) {
        self.ownerID = ownerID
    }

    func currentUser() async throws -> User {
        throw DemoAuthRequired.error
    }

    func profile(id: ProfileID) async throws -> Profile {
        if id == ownerID {
            return DemoCanonicalDataset.profile()
        }
        if id == DemoExploreTradeRoom.hostProfileID {
            return DemoExploreTradeRoom.hostProfile()
        }
        if id.rawValue.hasPrefix("dev."), let fixture = FollowListFixtures.profile(id: id) {
            return fixture
        }
        throw AppError.domain(.notFound(entity: "profile", id: id.rawValue))
    }

    func profiles(ids: [ProfileID]) async throws -> [Profile] {
        var result: [Profile] = []
        for id in Set(ids) {
            if let profile = try? await profile(id: id) {
                result.append(profile)
            }
        }
        return result
    }

    func profile(username: String) async throws -> Profile {
        if username == DemoCanonicalDataset.profile().username {
            return DemoCanonicalDataset.profile()
        }
        throw AppError.domain(.notFound(entity: "profile", id: username))
    }

    func ensureProfileExists(for profileID: ProfileID) async throws -> Profile {
        try await profile(id: profileID)
    }

    func onboardingSnapshot(for profileID: ProfileID, authoritative: Bool) async throws -> ProfileOnboardingSnapshot {
        ProfileOnboardingSnapshot(
            profileID: profileID,
            username: DemoCanonicalDataset.profile().username,
            displayName: DemoCanonicalDataset.profile().displayName,
            onboardingCompleted: true
        )
    }

    func isUsernameTaken(_ username: String, excluding profileID: ProfileID) async throws -> Bool { false }

    func completeProfileOnboarding(_ submission: ProfileOnboardingSubmission) async throws -> Profile {
        throw DemoAuthRequired.error
    }

    func updateProfile(_ profile: Profile) async throws -> Profile { throw DemoAuthRequired.error }

    func ownerProfileForSettings(id: ProfileID) async throws -> Profile { throw DemoAuthRequired.error }

    func updateProfileSettings(_ update: ProfileSettingsUpdate) async throws -> Profile {
        throw DemoAuthRequired.error
    }

    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        guard profileID == ownerID else {
            throw AppError.domain(.notFound(entity: "profile", id: profileID.rawValue))
        }
        return DemoCanonicalDataset.profileStats()
    }

    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        guard profileID == ownerID else {
            return CursorPage(items: [], nextCursor: nil)
        }
        return CursorPage(items: DemoCanonicalDataset.posts(), nextCursor: nil)
    }

    func wallPost(id: PostID) async throws -> Post {
        if let post = DemoCanonicalDataset.posts().first(where: { $0.id == id }) {
            return post
        }
        if let fixture = ProfilePostFixtures.post(id: id) {
            return fixture
        }
        throw AppError.domain(.notFound(entity: "post", id: id.rawValue))
    }

    func createWallPost(
        authorID: ProfileID,
        content: String,
        imageURL: String?,
        imageCrop: ContentImagePresentation?
    ) async throws -> Post {
        throw DemoAuthRequired.error
    }

    func deleteWallPost(id: PostID) async throws { throw DemoAuthRequired.error }

    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState { .none }

    func follow(from viewer: ProfileID, to target: ProfileID) async throws { throw DemoAuthRequired.error }

    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws { throw DemoAuthRequired.error }

    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func creator(for profileID: ProfileID) async throws -> Creator? { nil }

    func ownerDmPrivacy() async throws -> DmPrivacy { .everyone }

    func updateDmPrivacy(_ privacy: DmPrivacy) async throws -> DmPrivacy { throw DemoAuthRequired.error }
}

nonisolated struct DemoAchievementRepository: AchievementRepository {
    func achievements(
        for profileID: ProfileID,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Achievement> {
        guard profileID == DemoExperienceSupport.profileID else {
            return CursorPage(items: [], nextCursor: nil)
        }
        var items = DemoCanonicalDataset.achievements()
        if publicOnly {
            items = items.filter(\.isPublic)
        }
        return CursorPage(items: items, nextCursor: nil)
    }

    func achievement(id: AchievementID) async throws -> Achievement {
        if let match = DemoCanonicalDataset.achievements().first(where: { $0.id == id }) {
            return match
        }
        if let fixture = ProfileAchievementFixtures.achievement(id: id) {
            return fixture
        }
        throw AppError.domain(.notFound(entity: "achievement", id: id.rawValue))
    }

    func save(_ achievement: Achievement) async throws -> Achievement {
        throw DemoAuthRequired.error
    }
}

nonisolated struct DemoInteractionRepository: InteractionRepository {
    func engagement(for targets: [InteractionTarget]) async throws -> [InteractionTarget: EngagementSnapshot] {
        Dictionary(
            uniqueKeysWithValues: targets.map {
                ($0, EngagementSnapshot(likeCount: 0, commentCount: 0, viewerHasLiked: false))
            }
        )
    }

    func setLiked(_ liked: Bool, on target: InteractionTarget) async throws {
        throw DemoAuthRequired.error
    }

    func comments(for target: InteractionTarget, order: CommentSortOrder) async throws -> [InteractionComment] {
        []
    }

    func addComment(
        body: String,
        parentID: CommentID?,
        on target: InteractionTarget
    ) async throws -> InteractionComment {
        throw DemoAuthRequired.error
    }

    func deleteComment(id: CommentID, on target: InteractionTarget) async throws {
        throw DemoAuthRequired.error
    }

    func commentLikeMeta(
        for commentIDs: [CommentID],
        source: CommentLikeSource
    ) async throws -> [CommentID: CommentLikeSnapshot] {
        [:]
    }

    func setCommentLiked(_ liked: Bool, commentID: CommentID, source: CommentLikeSource) async throws {
        throw DemoAuthRequired.error
    }

    func setCommentPinned(_ pinned: Bool, commentID: CommentID, on target: InteractionTarget) async throws {
        throw DemoAuthRequired.error
    }
}

nonisolated struct DemoVaultRepository: VaultRepository {
    func state(for refs: [VaultContentRef]) async throws -> [VaultContentRef: VaultItemState] { [:] }
    func folders() async throws -> [VaultFolder] { [] }
    func createFolder(name: String) async throws -> VaultFolder { throw DemoAuthRequired.error }
    func renameFolder(id: VaultFolderID, name: String) async throws -> VaultFolder {
        throw DemoAuthRequired.error
    }
    func deleteFolder(id: VaultFolderID) async throws { throw DemoAuthRequired.error }
    func saveToVault(ref: VaultContentRef, folderID: VaultFolderID?) async throws -> VaultItem {
        throw DemoAuthRequired.error
    }
    func addToFolder(vaultItemID: VaultItemID, folderID: VaultFolderID) async throws {
        throw DemoAuthRequired.error
    }
    func removeFromFolder(vaultItemID: VaultItemID, folderID: VaultFolderID) async throws {
        throw DemoAuthRequired.error
    }
    func removeFromVault(vaultItemID: VaultItemID) async throws { throw DemoAuthRequired.error }
    func listItems(
        filter: VaultContentFilter,
        folderID: VaultFolderID?,
        cursor: String?,
        limit: Int
    ) async throws -> VaultListPage {
        VaultListPage(items: [], nextCursor: nil)
    }
}
