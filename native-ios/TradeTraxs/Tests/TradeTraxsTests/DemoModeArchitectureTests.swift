import XCTest
@testable import TradeTraxs

@MainActor
final class DemoModeArchitectureTests: XCTestCase {
    override func tearDown() {
        DemoExperienceSupport.setExploreLiveCommunityReadsActive(false)
        SessionViewerGate.shared.resetForTesting()
        ActivityInboxStore.shared.invalidate()
        DemoSnapshotStore.shared.clearMemory()
        super.tearDown()
    }

    func testCanonicalDatasetPopulatesJournalSurfacesFromTheSameTrades() {
        let trades = DemoCanonicalDataset.trades()
        let accounts = DemoCanonicalDataset.accounts()
        XCTAssertGreaterThanOrEqual(accounts.count, 3)
        XCTAssertFalse(trades.isEmpty)

        let accountIDs = Set(accounts.map(\.id))
        let tradeAccountIDs = Set(trades.compactMap(\.accountID))
        XCTAssertEqual(tradeAccountIDs, accountIDs)

        let wins = trades.filter { ($0.realizedPnL?.amount ?? 0) > 0 }
        let losses = trades.filter { ($0.realizedPnL?.amount ?? 0) < 0 }
        XCTAssertFalse(wins.isEmpty)
        XCTAssertFalse(losses.isEmpty)
        for account in accounts {
            let owned = trades.filter { $0.accountID == account.id }
            XCTAssertFalse(owned.isEmpty, account.name)
        }

        let combined = trades.reduce(Decimal(0)) { $0 + ($1.realizedPnL?.amount ?? 0) }
        let byAccount = accounts.reduce(Decimal(0)) { partial, account in
            partial + trades
                .filter { $0.accountID == account.id }
                .reduce(Decimal(0)) { $0 + ($1.realizedPnL?.amount ?? 0) }
        }
        XCTAssertEqual(combined, byAccount)

        let evaluation = netPnL(DemoCanonicalDataset.evaluationAccountID, trades: trades)
        let funded = netPnL(DemoCanonicalDataset.fundedAccountID, trades: trades)
        XCTAssertNotEqual(evaluation, funded)

        let checkIns = DemoCanonicalDataset.checkIns()
        let checkInDates = Set(checkIns.map(\.checkInDate))
        let tradeDates = Set(
            DemoCanonicalDataset.trades().map { TraderPsychologyAnalyticsFoundation.tradeDateKey(for: $0) }
        )
        XCTAssertFalse(checkInDates.isEmpty)
        XCTAssertEqual(
            checkInDates,
            tradeDates,
            "check-ins \(checkInDates.count) trades \(tradeDates.count)"
        )
    }

    func testSwitchingAccountsChangesDependentTotals() {
        let trades = DemoCanonicalDataset.trades()
        let all = netPnL(nil, trades: trades)
        let evaluation = netPnL(DemoCanonicalDataset.evaluationAccountID, trades: trades)
        let live = netPnL(DemoCanonicalDataset.liveAccountID, trades: trades)
        XCTAssertNotEqual(all, evaluation)
        XCTAssertNotEqual(evaluation, live)
    }

    func testBundledSocialFixturesStayAvailableWhileDemoInboxIsActive() {
        DemoExperienceSupport.setExploreLiveCommunityReadsActive(true)
        let viewer = DemoExperienceSupport.profileID
        XCTAssertTrue(DemoExperienceSupport.usesLocalBundledData(viewer))
        XCTAssertTrue(DemoExperienceSupport.usesLocalBundledSocialData(viewer))
        XCTAssertTrue(DemoExperienceSupport.usesExploreDemoInbox(viewer))
        XCTAssertFalse(FeedFixtures.timeline(viewerID: viewer).isEmpty)
        XCTAssertFalse(ActivityFixtures.notifications().isEmpty)
        XCTAssertEqual(
            DemoExploreTradeRoom.homeBootstrap(viewerID: viewer, scope: .yourRooms).yourRooms.first?.id,
            DemoExploreTradeRoom.roomID
        )
    }

    func testViewerGateAllowsDemoDashboardAfterSessionInvalidate() {
        SessionViewerGate.shared.endSession()
        XCTAssertFalse(
            SessionViewerGate.shared.allowsDisplay(owner: DemoExperienceSupport.profileID.rawValue)
        )
        SessionViewerGate.shared.bind(DemoExperienceSupport.profileID.rawValue)
        XCTAssertTrue(
            SessionViewerGate.shared.allowsDisplay(owner: DemoExperienceSupport.profileID.rawValue)
        )
    }

    func testExitingDemoClearsViewerAndInboxFlags() {
        DemoExperienceSupport.setExploreLiveCommunityReadsActive(true)
        SessionViewerGate.shared.bind(DemoExperienceSupport.profileID.rawValue)
        DemoExperienceSupport.setExploreLiveCommunityReadsActive(false)
        SessionViewerGate.shared.endSession()
        XCTAssertFalse(DemoExperienceSupport.usesExploreDemoInbox(DemoExperienceSupport.profileID))
        XCTAssertFalse(DemoExperienceSupport.skipsAuthenticatedViewerServices)
        XCTAssertFalse(
            SessionViewerGate.shared.allowsDisplay(owner: DemoExperienceSupport.profileID.rawValue)
        )
        XCTAssertFalse(SessionViewerGate.shared.allowsUnscopedFallback)
    }

    func testDemoModeDoesNotPresentProPaywall() {
        XCTAssertFalse(
            ProMonetizationPolicy.canPresentProPaywall(
                demoModeActive: true,
                enforcement: true,
                paywallEnabled: true
            )
        )
        XCTAssertTrue(
            ProMonetizationPolicy.canPresentProPaywall(
                demoModeActive: false,
                enforcement: true,
                paywallEnabled: true
            )
        )
    }

    func testDemoRepositoriesRefuseProductionMutations() async {
        let trades = DemoTradeRepository()
        do {
            try await trades.delete(id: TradeID("demo-trade-missing"))
            XCTFail("Expected demo trade delete to refuse")
        } catch let error as AppError {
            guard case .authentication(.sessionMissing) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error \(error)")
        }

        let vault = DemoVaultRepository()
        let page = try? await vault.listItems(filter: .all, folderID: nil, cursor: nil, limit: 20)
        XCTAssertFalse(page?.items.isEmpty ?? true)
        do {
            _ = try await vault.createFolder(name: "Live")
            XCTFail("Expected vault create to refuse")
        } catch let error as AppError {
            guard case .authentication(.sessionMissing) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testDemoSessionIdentityIsTheLocalProfile() async {
        let session = DemoSessionProvider()
        let userID = await session.currentUserID
        XCTAssertEqual(userID?.rawValue, DemoExperienceSupport.profileID.rawValue)
        let token = await session.accessToken
        XCTAssertNil(token)
    }

    func testDemoGraphReferencesResolveInsideTheCanonicalJournal() {
        let trades = DemoCanonicalDataset.trades()
        let tradeIDs = Set(trades.map(\.id))
        let profileIDs = Set(DemoGraph.profiles().map(\.id))
            .union([DemoExperienceSupport.profileID, DemoExploreTradeRoom.hostProfileID])

        let featured = DemoGraph.featuredTrade()
        XCTAssertTrue(tradeIDs.contains(featured.id))

        for notification in DemoGraph.notifications() {
            if let tradeID = notification.tradeID {
                XCTAssertTrue(tradeIDs.contains(tradeID), notification.id.rawValue)
            }
            if let actor = notification.actorProfileID {
                XCTAssertNotNil(DemoGraph.profile(id: actor), notification.id.rawValue)
            }
            if let postID = notification.postID {
                XCTAssertNotNil(DemoGraph.post(id: postID), notification.id.rawValue)
            }
            if notification.kind == .tradingReport {
                XCTAssertEqual(notification.reportID?.rawValue, TradingReportPeriodKey.monthlyLast.rawValue)
            }
            if notification.kind == .roomMention {
                XCTAssertEqual(notification.roomID, DemoExploreTradeRoom.roomID)
            }
        }

        let messages = DemoGraph.messages(
            conversationID: DemoGraph.sarahConversationID,
            viewerID: DemoExperienceSupport.profileID
        )
        XCTAssertFalse(messages.isEmpty)
        for message in messages {
            if case .trade(let tradeID) = message.sharedContent {
                XCTAssertTrue(tradeIDs.contains(tradeID))
            }
            XCTAssertTrue(profileIDs.contains(message.senderProfileID))
        }

        let feed = DemoGraph.feedEntries(viewerID: DemoExperienceSupport.profileID)
        XCTAssertFalse(feed.isEmpty)
        for entry in feed {
            XCTAssertNotNil(DemoGraph.profile(id: entry.authorProfileID))
            if let tradeID = entry.item.tradeID {
                XCTAssertTrue(tradeIDs.contains(tradeID))
            }
        }

        XCTAssertFalse(DemoGraph.posts().isEmpty)
        XCTAssertFalse(DemoGraph.clips().isEmpty)
        XCTAssertFalse(DemoGraph.followers().isEmpty)
        XCTAssertEqual(
            Set(DemoCanonicalDataset.posts().map(\.id)),
            Set(DemoGraph.posts().map(\.id))
        )
    }

    func testActivityStoreLoadsBundledRowsForDemoViewer() async {
        let session = DemoSessionProvider()
        let cache = DetailPresentationCache()
        await ActivityInboxStore.shared.startIfNeeded(
            notifications: UnavailableNotificationRepository(),
            followRequests: nil,
            session: session,
            realtimeHub: nil,
            detailCache: cache
        )
        XCTAssertTrue(ActivityInboxStore.shared.hasLoaded)
        XCTAssertFalse(ActivityInboxStore.shared.items.isEmpty)
        XCTAssertGreaterThan(ActivityInboxStore.shared.unreadCount, 0)
    }

    private func netPnL(_ accountID: TradingAccountID?, trades: [Trade]) -> Decimal {
        trades.reduce(Decimal(0)) { partial, trade in
            guard accountID == nil || trade.accountID == accountID else { return partial }
            return partial + (trade.realizedPnL?.amount ?? 0)
        }
    }
}

private struct UnavailableNotificationRepository: NotificationRepository {
    func notifications(page: PageRequest) async throws -> CursorPage<ActivityNotification> {
        _ = page
        throw AppError.cancelled
    }

    func notification(id: NotificationID) async throws -> ActivityNotification? {
        _ = id
        throw AppError.cancelled
    }

    func unreadCount() async throws -> Int { throw AppError.cancelled }

    func markRead(id: NotificationID) async throws { _ = id }

    func markRead(ids: [NotificationID]) async throws -> Int {
        _ = ids
        return 0
    }

    func markMessageNotificationsRead() async throws -> Int { 0 }

    func markRoomNotificationsRead(roomID: RoomID, slug: String?) async throws -> Int {
        _ = (roomID, slug)
        return 0
    }

    func markAllRead() async throws {}

    func delete(id: NotificationID) async throws { _ = id }

    func delete(ids: [NotificationID]) async throws -> Int {
        _ = ids
        return 0
    }

    func profiles(ids: [ProfileID]) async throws -> [Profile] {
        _ = ids
        return []
    }
}
