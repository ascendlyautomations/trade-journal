import XCTest
@testable import TradeTraxs

final class DemoSnapshotTests: XCTestCase {
    override func tearDown() {
        DemoSnapshotStore.shared.clearMemory()
        super.tearDown()
    }

    func testBundledSnapshotValidatesAndRoundTripsRelationships() throws {
        let snapshot = DemoSnapshot.captureBundled(version: 1)
        XCTAssertTrue(snapshot.validate().isEmpty, snapshot.validate().joined(separator: ","))

        let decoded = try DemoSnapshotCoding.decode(DemoSnapshotCoding.encode(snapshot))
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.schemaVersion, DemoSnapshot.currentSchemaVersion)
        XCTAssertEqual(Set(decoded.trades.map(\.id)), Set(snapshot.trades.map(\.id)))
        XCTAssertEqual(Set(decoded.accounts.map(\.id)), Set(snapshot.accounts.map(\.id)))

        let tradeIDs = Set(decoded.trades.map(\.id))
        let featured = decoded.activity.compactMap(\.tradeID)
        XCTAssertTrue(featured.allSatisfy(tradeIDs.contains))
        let shared = decoded.messages.compactMap { message -> TradeID? in
            guard case .trade(let id) = message.sharedContent else { return nil }
            return id
        }
        XCTAssertFalse(shared.isEmpty)
        XCTAssertTrue(shared.allSatisfy(tradeIDs.contains))
        XCTAssertEqual(
            decoded.activity.first { $0.kind == .tradingReport }?.reportID?.rawValue,
            "monthly_last"
        )
    }

    func testMalformedSnapshotIsRejectedAndLastKnownGoodStays() throws {
        let store = DemoSnapshotStore(cacheFileURL: temporaryFile())
        let good = DemoSnapshot.captureBundled(version: 2)
        XCTAssertEqual(store.ingestRemoteData(try DemoSnapshotCoding.encode(good)), .applied(version: 2))

        var broken = good
        broken.trades[0].accountID = TradingAccountID("missing-account")
        XCTAssertFalse(broken.validate().isEmpty)
        XCTAssertEqual(store.ingestRemoteData(try DemoSnapshotCoding.encode(broken)), .rejected)
        XCTAssertEqual(store.current?.version, 2)
        XCTAssertEqual(store.ingestRemoteData(Data("not-json".utf8)), .rejected)
        XCTAssertEqual(store.current?.version, 2)
    }

    func testOlderRemoteVersionDoesNotReplaceCache() throws {
        let store = DemoSnapshotStore(cacheFileURL: temporaryFile())
        let newer = DemoSnapshot.captureBundled(version: 3)
        XCTAssertEqual(store.ingestRemoteData(try DemoSnapshotCoding.encode(newer)), .applied(version: 3))
        var older = newer
        older.version = 1
        XCTAssertEqual(store.ingestRemoteData(try DemoSnapshotCoding.encode(older)), .unchanged(version: 3))
        XCTAssertEqual(store.current?.version, 3)
    }

    func testDiskCacheReloadsAndInvalidCacheFallsBackToBundled() throws {
        let url = temporaryFile()
        let store = DemoSnapshotStore(cacheFileURL: url)
        var snapshot = DemoSnapshot.captureBundled(version: 4)
        snapshot.accounts[0].name = "Published Apex"
        XCTAssertEqual(store.ingestRemoteData(try DemoSnapshotCoding.encode(snapshot)), .applied(version: 4))

        let reloaded = DemoSnapshotStore(cacheFileURL: url)
        let cached = reloaded.activateCachedSnapshot()
        XCTAssertEqual(cached?.version, 4)
        XCTAssertEqual(cached?.accounts.first?.name, "Published Apex")

        try Data("{".utf8).write(to: url)
        let rejected = DemoSnapshotStore(cacheFileURL: url)
        XCTAssertNil(rejected.activateCachedSnapshot())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(DemoCanonicalDataset.accounts().contains { $0.name == "Published Apex" })
    }

    func testInstalledSnapshotFeedsTheExistingDatasetAndClearReturnsToBundled() throws {
        var snapshot = DemoSnapshot.captureBundled(version: 5)
        snapshot.accounts[0].name = "Published Apex"
        DemoSnapshotStore.shared.install(snapshot)
        XCTAssertTrue(DemoCanonicalDataset.accounts().contains { $0.name == "Published Apex" })
        XCTAssertEqual(DemoGraph.notifications().count, snapshot.activity.count)
        XCTAssertEqual(DemoExploreTradeRoom.room().id, snapshot.room.id)

        DemoSnapshotStore.shared.clearMemory()
        XCTAssertFalse(DemoCanonicalDataset.accounts().contains { $0.name == "Published Apex" })
        XCTAssertFalse(DemoCanonicalDataset.trades().isEmpty)
    }

    func testUnavailableNetworkKeepsBundledSourceWhenNothingIsCached() async {
        let store = DemoSnapshotStore(cacheFileURL: temporaryFile())
        let result = await store.refresh(timeoutNanoseconds: 50_000_000) {
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(result, .unavailable)
        XCTAssertNil(store.current)
    }

    func testSlowHigherSnapshotReplacesTheCachedOne() async throws {
        let store = DemoSnapshotStore(cacheFileURL: temporaryFile())
        let cached = DemoSnapshot.captureBundled(version: 6)
        XCTAssertEqual(store.ingestRemoteData(try DemoSnapshotCoding.encode(cached)), .applied(version: 6))
        var newer = cached
        newer.version = 7
        let result = await store.refresh(timeoutNanoseconds: 1_000_000) {
            try await Task.sleep(nanoseconds: 80_000_000)
            return try DemoSnapshotCoding.encode(newer)
        }
        XCTAssertEqual(result, .applied(version: 7))
        XCTAssertEqual(store.current?.version, 7)
    }

    func testIncompleteAdminActivityDoesNotBlockANewerSnapshot() throws {
        let store = DemoSnapshotStore(cacheFileURL: temporaryFile())
        let cached = DemoSnapshot.captureBundled(version: 7)
        XCTAssertEqual(store.ingestRemoteData(try DemoSnapshotCoding.encode(cached)), .applied(version: 7))

        let encoded = try DemoSnapshotCoding.encode(cached)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var activity = try XCTUnwrap(root["activity"] as? [Any])
        activity.append([
            "id": "demo.activity.extra",
            "kind": "follow",
            "title": "like",
            "body": "Alex started following you",
            "tradeID": "",
            "createdAt": "2026-10-04T03:42:51Z",
            "actorProfileID": DemoGraph.alexID.rawValue,
        ] as [String: Any])
        root["activity"] = activity
        root["version"] = 8
        let published = try JSONSerialization.data(withJSONObject: root)
        XCTAssertEqual(store.ingestRemoteData(published), .applied(version: 8))
        XCTAssertEqual(store.current?.version, 8)
        XCTAssertNil(store.current?.activity.last?.tradeID)
        XCTAssertEqual(store.current?.activity.last?.isRead, false)
        XCTAssertEqual(store.current?.activity.last?.isReply, false)
    }

    func testAvatarURLBecomesTheActiveDemoProfile() throws {
        var snapshot = DemoSnapshot.captureBundled(version: 9)
        let url = "https://cdn.example.com/storage/v1/object/public/demo-media/demo/profile/demo.explore.trader/avatar.jpg"
        snapshot.viewer.avatar = MediaReference(id: url, kind: .image, altText: "avatar")
        let decoded = try DemoSnapshotCoding.decode(try DemoSnapshotCoding.encode(snapshot))
        XCTAssertEqual(decoded.viewer.avatar?.id, url)
        DemoSnapshotStore.shared.install(decoded)
        XCTAssertEqual(DemoCanonicalDataset.profile().avatar?.id, url)
    }

    func testHigherSnapshotBecomesTheActiveDemoJournal() async throws {
        var stale = DemoSnapshot.captureBundled(version: 3)
        DemoSnapshotStore.shared.install(stale)
        let repository = DemoTradeRepository()
        let tradeID = stale.trades[0].id
        let before = try await repository.trade(id: tradeID)
        stale.version = 4
        stale.trades[0].realizedPnL = Money(amount: 4242, currencyCode: "USD")
        DemoSnapshotStore.shared.install(stale)
        let after = try await repository.trade(id: tradeID)
        XCTAssertEqual(after.realizedPnL?.amount, Decimal(4242))
        XCTAssertNotEqual(before.realizedPnL?.amount, after.realizedPnL?.amount)
    }

    func testDemoMessagesLoadFromTheSnapshotWithoutAProductionSession() async throws {
        let snapshot = DemoSnapshot.captureBundled(version: 8)
        DemoSnapshotStore.shared.install(snapshot)
        let repository = DemoExploreMessageRepository()
        let list = try await repository.conversations(page: PageRequest(limit: 20))
        let sarah = try XCTUnwrap(list.items.first { $0.id == DemoGraph.sarahConversationID })
        XCTAssertTrue(sarah.participantProfileIDs.contains(DemoExperienceSupport.profileID))
        XCTAssertNotNil(DemoGraph.profile(id: DemoGraph.sarahID))
        let page = try await repository.messages(in: DemoGraph.sarahConversationID, page: PageRequest(limit: 20))
        XCTAssertFalse(page.items.isEmpty)
        XCTAssertTrue(page.items.contains { message in
            if case .trade = message.sharedContent { return true }
            return false
        })
        let sharedTradeID: TradeID? = page.items.compactMap { message in
            if case .trade(let id) = message.sharedContent { return id }
            return nil
        }.first
        let tradeID = try XCTUnwrap(sharedTradeID)
        let trade = try await DemoTradeRepository().trade(id: tradeID)
        XCTAssertEqual(trade.id, tradeID)
    }

    func testExportBundledSnapshotWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["DEMO_SNAPSHOT_EXPORT"] else { return }
        let data = try DemoSnapshotCoding.encode(DemoSnapshot.captureBundled(version: 1))
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("demo-snapshot-\(UUID().uuidString).json")
    }
}
