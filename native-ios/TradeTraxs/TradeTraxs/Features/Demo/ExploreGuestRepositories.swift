import Foundation

// MARK: - Guest public community (anon RPC / RLS only)

/// Feed timeline loads exclusively via ``FeedBootstrapLoader`` guest RPC — no REST / block sync.
nonisolated struct GuestPublicFeedRepository: FeedRepository, @unchecked Sendable {
    private let publicReads: DefaultFeedRepository?

    init(supabase: SupabaseInfrastructure, cache: CacheStack, session: any SessionProviding) {
        self.publicReads = DefaultFeedRepository(supabase: supabase, cache: cache, session: session)
    }

    private func unavailable() -> AppError { .notImplemented(feature: "guestFeedREST") }

    func feed(
        scope: FeedScope,
        contentFilter: FeedContentFilter,
        page: PageRequest
    ) async throws -> FeedPageResult {
        throw unavailable()
    }

    func post(id: PostID) async throws -> Post {
        guard let publicReads else { throw unavailable() }
        return try await publicReads.post(id: id)
    }

    func posts(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        guard let publicReads else { throw unavailable() }
        return try await publicReads.posts(authoredBy: profileID, page: page)
    }

    func createPost(_ post: Post) async throws -> Post { throw DemoAuthRequired.error }
    func deletePost(id: PostID) async throws { throw DemoAuthRequired.error }

    func comments(for postID: PostID, page: PageRequest) async throws -> CursorPage<Comment> {
        guard let publicReads else { throw unavailable() }
        return try await publicReads.comments(for: postID, page: page)
    }

    func addComment(_ comment: Comment) async throws -> Comment { throw DemoAuthRequired.error }
    func setReaction(on item: FeedItem, kind: ReactionKind, isActive: Bool) async throws {
        throw DemoAuthRequired.error
    }

    func stories(for viewer: ProfileID) async throws -> [Story] { [] }
    func allActiveStories(for viewer: ProfileID) async throws -> [Story] { [] }

    func story(id: StoryID) async throws -> Story? {
        guard let publicReads else { return nil }
        return try await publicReads.story(id: id)
    }

    func createStory(userID: ProfileID, imageURL: String) async throws -> Story { throw DemoAuthRequired.error }
    func deleteStory(id: StoryID) async throws { throw DemoAuthRequired.error }

    func reel(id: ReelID) async throws -> ReelLoadResult {
        guard let publicReads else { throw unavailable() }
        return try await publicReads.reel(id: id)
    }

    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        guard let publicReads else { throw unavailable() }
        return try await publicReads.reels(authoredBy: profileID, page: page)
    }

    func profileReels(for profileID: ProfileID) async throws -> ProfileReelsResult {
        guard let publicReads else { throw unavailable() }
        return try await publicReads.profileReels(for: profileID)
    }

    func createReel(_ reel: Reel) async throws -> Reel { throw DemoAuthRequired.error }
    func deleteReel(id: ReelID) async throws { throw DemoAuthRequired.error }
    func unattachedReels(for profileID: ProfileID, limit: Int) async throws -> [Reel] { [] }
}

nonisolated struct GuestPublicExploreRepository: ExploreRepository, @unchecked Sendable {
    private let live: DefaultExploreRepository

    init(supabase: SupabaseInfrastructure) {
        self.live = DefaultExploreRepository(supabase: supabase)
    }

    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile> {
        try await live.discoverableProfiles(page: page)
    }

    func socialCounts(for profileIDs: [ProfileID]) async throws -> ExploreSocialCounts {
        try await live.socialCounts(for: profileIDs)
    }

    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary] {
        try await live.tradeActivitySummaries(limit: limit)
    }

    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion] {
        try await live.popularRooms(limit: limit)
    }

    func discoverRooms(
        mode: TradeRoomDiscoveryMode,
        scope: TradeRoomDiscoveryScope,
        limit: Int
    ) async throws -> [ExploreRoomSuggestion] {
        try await live.discoverRooms(mode: mode, scope: scope, limit: limit)
    }

    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] {
        try await live.searchRooms(query: query, limit: limit)
    }

    func tradeRoomsHomeBootstrap(
        scope: TradeRoomDiscoveryScope,
        limit: Int
    ) async throws -> TradeRoomsHomeBootstrap {
        try await live.tradeRoomsHomeBootstrap(scope: scope, limit: limit)
    }
}

/// Public room metadata reads only — membership / messaging writes blocked for guests.
nonisolated struct GuestPublicRoomsRepository: RoomRepository, @unchecked Sendable {
    private let live: DefaultRoomRepository

    init(supabase: SupabaseInfrastructure, cache: CacheStack) {
        self.live = DefaultRoomRepository(supabase: supabase, cache: cache)
    }

    func room(id: RoomID) async throws -> TradeRoom { try await live.room(id: id) }
    func rooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        try await live.rooms(for: profileID, page: page)
    }
    func memberRooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        CursorPage(items: [], nextCursor: nil)
    }
    func activeMemberCounts(for roomIDs: [RoomID]) async throws -> [RoomID: Int] {
        try await live.activeMemberCounts(for: roomIDs)
    }
    func unreadCounts(for roomIDs: [RoomID]) async throws -> [RoomID: Int] { [:] }
    func lastMessageActivity(for roomIDs: [RoomID]) async throws -> [RoomID: Date] { [:] }
    func markRead(roomID: RoomID) async throws {}
    func channels(roomID: RoomID) async throws -> [RoomChannel] { try await live.channels(roomID: roomID) }
    func membership(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership? { nil }
    func join(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership { throw DemoAuthRequired.error }
    func leave(roomID: RoomID, profileID: ProfileID) async throws { throw DemoAuthRequired.error }
    func messages(roomID: RoomID, page: PageRequest) async throws -> CursorPage<RoomMessage> {
        try await live.messages(roomID: roomID, page: page)
    }
    func messages(
        roomID: RoomID,
        channel: RoomChannel?,
        page: PageRequest
    ) async throws -> CursorPage<RoomMessage> {
        try await live.messages(roomID: roomID, channel: channel, page: page)
    }
    func send(_ message: RoomMessage) async throws -> RoomMessage { throw DemoAuthRequired.error }
    func deleteMessage(roomID: RoomID, messageID: RoomMessageID) async throws {
        throw DemoAuthRequired.error
    }
    func insertMessageReaction(
        roomID: RoomID,
        messageID: RoomMessageID,
        userID: ProfileID,
        reaction: String
    ) async throws -> RoomMessageReaction {
        throw DemoAuthRequired.error
    }
    func deleteMessageReaction(id: String) async throws { throw DemoAuthRequired.error }
    func moderate(
        roomID: RoomID,
        messageID: RoomMessageID?,
        targetProfileID: ProfileID?,
        action: RoomModerationAction
    ) async throws {
        throw DemoAuthRequired.error
    }
    func requestJoin(roomID: RoomID) async throws -> TradeRoomJoinRequestState { throw DemoAuthRequired.error }
    func viewerJoinRequest(roomID: RoomID) async throws -> TradeRoomJoinRequestState? { nil }
}

/// Guest public rooms + local Explore demo room (never hits Supabase for demo IDs).
nonisolated struct DemoExploreRoomsRepository: RoomRepository, @unchecked Sendable {
    private let guest: GuestPublicRoomsRepository

    init(supabase: SupabaseInfrastructure, cache: CacheStack) {
        self.guest = GuestPublicRoomsRepository(supabase: supabase, cache: cache)
    }

    private func localOrGuest<T>(
        roomID: RoomID,
        local: () throws -> T,
        remote: () async throws -> T
    ) async throws -> T {
        if DemoExploreTradeRoom.isLocalRoom(roomID) {
            return try local()
        }
        return try await remote()
    }

    func room(id: RoomID) async throws -> TradeRoom {
        try await localOrGuest(roomID: id, local: { DemoExploreTradeRoom.room() }, remote: { try await guest.room(id: id) })
    }

    func rooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        try await guest.rooms(for: profileID, page: page)
    }

    func memberRooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        try await guest.memberRooms(for: profileID, page: page)
    }

    func activeMemberCounts(for roomIDs: [RoomID]) async throws -> [RoomID: Int] {
        try await guest.activeMemberCounts(for: roomIDs)
    }

    func unreadCounts(for roomIDs: [RoomID]) async throws -> [RoomID: Int] {
        try await guest.unreadCounts(for: roomIDs)
    }

    func lastMessageActivity(for roomIDs: [RoomID]) async throws -> [RoomID: Date] {
        try await guest.lastMessageActivity(for: roomIDs)
    }

    func markRead(roomID: RoomID) async throws {
        guard !DemoExploreTradeRoom.isLocalRoom(roomID) else { return }
        try await guest.markRead(roomID: roomID)
    }

    func channels(roomID: RoomID) async throws -> [RoomChannel] {
        try await localOrGuest(
            roomID: roomID,
            local: { DemoExploreTradeRoom.channels(roomID: roomID) },
            remote: { try await guest.channels(roomID: roomID) }
        )
    }

    func membership(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership? {
        guard !DemoExploreTradeRoom.isLocalRoom(roomID) else { return nil }
        return try await guest.membership(roomID: roomID, profileID: profileID)
    }

    func join(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership {
        guard !DemoExploreTradeRoom.isLocalRoom(roomID) else { throw DemoAuthRequired.error }
        return try await guest.join(roomID: roomID, profileID: profileID)
    }

    func leave(roomID: RoomID, profileID: ProfileID) async throws {
        guard !DemoExploreTradeRoom.isLocalRoom(roomID) else { throw DemoAuthRequired.error }
        try await guest.leave(roomID: roomID, profileID: profileID)
    }

    func messages(roomID: RoomID, page: PageRequest) async throws -> CursorPage<RoomMessage> {
        try await localOrGuest(
            roomID: roomID,
            local: {
                CursorPage(
                    items: DemoExploreTradeRoom.messages(roomID: roomID, viewerID: DemoExperienceSupport.profileID),
                    nextCursor: nil
                )
            },
            remote: { try await guest.messages(roomID: roomID, page: page) }
        )
    }

    func messages(
        roomID: RoomID,
        channel: RoomChannel?,
        page: PageRequest
    ) async throws -> CursorPage<RoomMessage> {
        try await localOrGuest(
            roomID: roomID,
            local: {
                CursorPage(
                    items: DemoExploreTradeRoom.messages(
                        roomID: roomID,
                        viewerID: DemoExperienceSupport.profileID,
                        channelID: channel?.id
                    ),
                    nextCursor: nil
                )
            },
            remote: { try await guest.messages(roomID: roomID, channel: channel, page: page) }
        )
    }

    func send(_ message: RoomMessage) async throws -> RoomMessage { throw DemoAuthRequired.error }
    func deleteMessage(roomID: RoomID, messageID: RoomMessageID) async throws {
        throw DemoAuthRequired.error
    }
    func insertMessageReaction(
        roomID: RoomID,
        messageID: RoomMessageID,
        userID: ProfileID,
        reaction: String
    ) async throws -> RoomMessageReaction {
        throw DemoAuthRequired.error
    }
    func deleteMessageReaction(id: String) async throws { throw DemoAuthRequired.error }
    func moderate(
        roomID: RoomID,
        messageID: RoomMessageID?,
        targetProfileID: ProfileID?,
        action: RoomModerationAction
    ) async throws {
        throw DemoAuthRequired.error
    }
    func requestJoin(roomID: RoomID) async throws -> TradeRoomJoinRequestState { throw DemoAuthRequired.error }
    func viewerJoinRequest(roomID: RoomID) async throws -> TradeRoomJoinRequestState? { nil }
}

/// Public trade cards from Feed deep links; demo owner journal stays local.
nonisolated struct GuestPublicTradeAccessRepository: TradeRepository, @unchecked Sendable {
    private let demo: DemoTradeRepository
    private let live: DefaultTradeRepository

    init(
        demo: DemoTradeRepository = DemoTradeRepository(),
        supabase: SupabaseInfrastructure,
        cache: CacheStack,
        session: any SessionProviding
    ) {
        self.demo = demo
        self.live = DefaultTradeRepository(supabase: supabase, cache: cache, session: session)
    }

    func trade(id: TradeID) async throws -> Trade {
        if let match = try? await demo.trade(id: id) { return match }
        return try await live.trade(id: id)
    }

    func trades(ids: [TradeID]) async throws -> [Trade] {
        var byID: [TradeID: Trade] = [:]
        for id in Set(ids) {
            if let trade = try? await demo.trade(id: id) { byID[id] = trade }
        }
        let missing = ids.filter { byID[$0] == nil }
        if !missing.isEmpty {
            for trade in try await live.trades(ids: missing) {
                byID[trade.id] = trade
            }
        }
        return ids.compactMap { byID[$0] }
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        guard profileID == DemoExperienceSupport.profileID else {
            return try await live.trades(
                ownedBy: profileID,
                accountID: accountID,
                page: page,
                publicOnly: true
            )
        }
        return try await demo.trades(
            ownedBy: profileID,
            accountID: accountID,
            page: page,
            publicOnly: publicOnly
        )
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        entryFrom: Date,
        entryTo: Date,
        limit: Int
    ) async throws -> [Trade] {
        guard profileID == DemoExperienceSupport.profileID else {
            return try await live.trades(
                ownedBy: profileID,
                accountID: accountID,
                entryFrom: entryFrom,
                entryTo: entryTo,
                limit: limit
            )
        }
        return try await demo.trades(
            ownedBy: profileID,
            accountID: accountID,
            entryFrom: entryFrom,
            entryTo: entryTo,
            limit: limit
        )
    }

    func tradeHistory(
        ownedBy profileID: ProfileID,
        query: TradeHistoryQuery,
        page: PageRequest
    ) async throws -> CursorPage<Trade> {
        guard profileID == DemoExperienceSupport.profileID else {
            return try await live.tradeHistory(ownedBy: profileID, query: query, page: page)
        }
        return try await demo.tradeHistory(ownedBy: profileID, query: query, page: page)
    }

    func statistics(for profileID: ProfileID, interval: DateIntervalValue) async throws -> TradeStatistics {
        guard profileID == DemoExperienceSupport.profileID else {
            return try await live.statistics(for: profileID, interval: interval)
        }
        return try await demo.statistics(for: profileID, interval: interval)
    }

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] {
        guard profileID == DemoExperienceSupport.profileID else {
            return try await live.accounts(for: profileID)
        }
        return try await demo.accounts(for: profileID)
    }

    func images(for tradeID: TradeID) async throws -> [TradeImage] {
        if let images = try? await demo.images(for: tradeID), !images.isEmpty { return images }
        return try await live.images(for: tradeID)
    }

    func notes(for tradeID: TradeID) async throws -> [TradeNote] {
        if let notes = try? await demo.notes(for: tradeID), !notes.isEmpty { return notes }
        return try await live.notes(for: tradeID)
    }

    func payoutEntries(for accountID: TradingAccountID) async throws -> [AccountPayoutEntry] {
        try await demo.payoutEntries(for: accountID)
    }

    func payoutEntries(for accountIDs: [TradingAccountID]) async throws -> [AccountPayoutEntry] {
        try await demo.payoutEntries(for: accountIDs)
    }

    func profileAccountInsights(for profileID: ProfileID) async throws -> [ProfileAccountInsight] {
        guard profileID == DemoExperienceSupport.profileID else {
            return try await live.profileAccountInsights(for: profileID)
        }
        return try await demo.profileAccountInsights(for: profileID)
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
}

/// Local demo DMs only — never hits ``rpc_v2_messaging_bootstrap``.
nonisolated struct DemoExploreMessageRepository: MessageRepository, @unchecked Sendable {
    private let viewerID: ProfileID

    init(viewerID: ProfileID = DemoExperienceSupport.profileID) {
        self.viewerID = viewerID
    }

    func conversations(page: PageRequest) async throws -> ConversationListResult {
        let items = DemoExploreInboxFixtures.conversations(viewerID: viewerID)
        let profiles = DemoExploreInboxFixtures.profiles(for: items, viewerID: viewerID)
        return ConversationListResult(items: items, nextCursor: nil, embeddedProfiles: profiles)
    }

    func conversation(id: ConversationID) async throws -> Conversation {
        let items = DemoExploreInboxFixtures.conversations(viewerID: viewerID)
        guard let match = items.first(where: { $0.id == id }) else {
            throw AppError.domain(.notFound(entity: "conversation", id: id.rawValue))
        }
        return match
    }

    func messages(in conversationID: ConversationID, page: PageRequest) async throws -> CursorPage<Message> {
        let conversation = try await conversation(id: conversationID)
        let peer = MessagesInboxSupport.peerID(in: conversation, viewerID: viewerID) ?? viewerID
        let items = DemoExploreInboxFixtures.messages(
            conversationID: conversationID,
            viewerID: viewerID,
            peerID: peer
        )
        return CursorPage(items: items, nextCursor: nil)
    }

    func send(_ message: Message) async throws -> Message { throw DemoAuthRequired.error }
    func markRead(conversationID: ConversationID) async throws {}
    func markUnread(conversationID: ConversationID) async throws { throw DemoAuthRequired.error }
    func createConversation(participantIDs: [ProfileID]) async throws -> Conversation {
        throw DemoAuthRequired.error
    }

    func findExistingDirectConversationID(viewerID: ProfileID, recipientID: ProfileID) async throws -> ConversationID? {
        nil
    }

    func usersHaveActiveBlock(viewerID: ProfileID, otherID: ProfileID) async -> Bool { false }

    func createDirectConversation(viewerID: ProfileID, recipient: Profile) async throws -> Conversation {
        throw DemoAuthRequired.error
    }

    func createGroupConversation(
        viewerID: ProfileID,
        recipients: [Profile],
        name: String?
    ) async throws -> Conversation {
        throw DemoAuthRequired.error
    }

    func deleteConversation(id: ConversationID) async throws { throw DemoAuthRequired.error }
    func deleteMessageForEveryone(_ messageID: MessageID, in conversationID: ConversationID) async throws {
        throw DemoAuthRequired.error
    }

    func setConversationNotificationsEnabled(conversationID: ConversationID, enabled: Bool) async throws {
        throw DemoAuthRequired.error
    }
}
