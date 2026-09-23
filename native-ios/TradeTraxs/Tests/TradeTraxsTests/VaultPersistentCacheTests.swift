import XCTest
@testable import TradeTraxs

@MainActor
final class VaultPersistentCacheTests: XCTestCase {
    private let viewerA = ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private let viewerB = ProfileID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")

    override func setUp() {
        super.setUp()
        VaultPersistedCacheTestHooks.forceSynchronousDiskWrites = true
        VaultPersistedCacheGeneration.resetForTesting()
    }

    override func tearDown() {
        VaultPersistedCacheCoordinator.flushPendingDiskWritesForTesting()
        VaultPersistedCacheTestHooks.forceSynchronousDiskWrites = false
        VaultPersistedCacheCoordinator.clearAll()
        VaultPersistedCacheGeneration.resetForTesting()
        super.tearDown()
    }

    func testDiskRoundTripHydratesStore() async {
        let store = makeStore(viewer: viewerA)
        let ref = VaultContentRef(contentType: .trade, contentID: "trade-vault-1")
        let item = VaultItem(
            id: VaultItemID("vault-item-1"),
            ref: ref,
            createdAt: .now,
            folderIDs: []
        )
        store.seedHome(
            items: [item],
            folders: [makeFolder(id: "folder-1")],
            nextCursor: nil,
            filter: .all,
            folderID: nil,
            shouldPersist: false
        )
        await VaultPersistedCacheCoordinator.shared.persistVaultPresentation(reason: "test", isRollback: false)
        VaultPersistedCacheCoordinator.flushPendingDiskWritesForTesting()

        store.removeAll()
        wirePersistence(store: store, viewer: viewerA)
        let hydrated = await VaultPersistedCacheCoordinator.shared.hydrateIfNeeded(
            store: store,
            filter: .all,
            folderID: nil
        )
        XCTAssertTrue(hydrated)
        XCTAssertEqual(store.cachedHome(filter: .all, folderID: nil)?.items.first?.ref, ref)
        XCTAssertTrue(store.state(for: ref).isVaulted)
    }

    func testViewerIsolation() async {
        let storeA = makeStore(viewer: viewerA)
        storeA.seedHome(
            items: [makeItem(id: "item-a", contentID: "secret-a")],
            folders: [],
            nextCursor: nil,
            filter: .all,
            folderID: nil
        )
        await VaultPersistedCacheCoordinator.shared.persistVaultPresentation(reason: "test", isRollback: false)

        let storeB = makeStore(viewer: viewerB)
        let hydrated = await VaultPersistedCacheCoordinator.shared.hydrateIfNeeded(
            store: storeB,
            filter: .all,
            folderID: nil
        )
        XCTAssertFalse(hydrated)
        XCTAssertNil(VaultDiskCache.loadSnapshot(viewerID: viewerB))
    }

    func testSoftStaleHonoredAfterDiskHydrate() async {
        let store = makeStore(viewer: viewerA)
        let loadedAt = Date(timeIntervalSinceNow: -400)
        store.seedHome(
            items: [makeItem(id: "stale-1", contentID: "c-1")],
            folders: [],
            nextCursor: nil,
            filter: .all,
            folderID: nil,
            loadedAt: loadedAt,
            shouldPersist: false
        )
        await VaultPersistedCacheCoordinator.shared.persistVaultPresentation(reason: "test", isRollback: false)
        VaultPersistedCacheCoordinator.flushPendingDiskWritesForTesting()
        store.removeAll()
        wirePersistence(store: store, viewer: viewerA)
        let hydrated = await VaultPersistedCacheCoordinator.shared.hydrateIfNeeded(
            store: store,
            filter: .all,
            folderID: nil
        )
        XCTAssertTrue(hydrated)
        let restoredLoadedAt = store.cachedHome(filter: .all, folderID: nil)?.loadedAt
        XCTAssertGreaterThan(Date().timeIntervalSince(restoredLoadedAt ?? .now), 300)
    }

    func testFailedSaveRollsBackDisk() async {
        let repository = FailingVaultRepository(failSave: true)
        let store = VaultStore(repository: repository)
        wirePersistence(store: store, viewer: viewerA)
        store.seedHome(items: [], folders: [], nextCursor: nil, filter: .all, folderID: nil)

        let ref = VaultContentRef(contentType: .trade, contentID: "fail-save")
        _ = await store.save(ref, folderID: nil, confirmation: "Added")

        let disk = VaultDiskCache.loadSnapshot(viewerID: viewerA)
        XCTAssertFalse(store.state(for: ref).isVaulted)
        XCTAssertNil(disk?.states[ref.cacheKey]?.vaultItemID)
    }

    func testRemovePatchesDisk() async {
        let ref = VaultContentRef(contentType: .trade, contentID: "remove-me")
        let repository = InMemoryVaultRepository()
        let wired = VaultStore(repository: repository)
        wirePersistence(store: wired, viewer: viewerA)
        wired.seedHome(
            items: [makeItem(id: "vi-1", contentID: "remove-me")],
            folders: [],
            nextCursor: nil,
            filter: .all,
            folderID: nil
        )

        _ = await wired.removeFromVault(ref)
        let disk = VaultDiskCache.loadSnapshot(viewerID: viewerA)
        XCTAssertFalse(wired.state(for: ref).isVaulted)
        XCTAssertTrue(disk?.homePages.first?.items.isEmpty == true)
    }

    func testFolderDeletePreservesOtherMembership() async {
        let store = makeStore(viewer: viewerA)
        let folderA = VaultFolderID("folder-a")
        let folderB = VaultFolderID("folder-b")
        let ref = VaultContentRef(contentType: .trade, contentID: "multi-folder")
        store.seedHome(
            items: [
                VaultItem(
                    id: VaultItemID("vi-multi"),
                    ref: ref,
                    createdAt: .now,
                    folderIDs: [folderA, folderB]
                ),
            ],
            folders: [
                makeFolder(id: folderA.rawValue, name: "A"),
                makeFolder(id: folderB.rawValue, name: "B"),
            ],
            nextCursor: nil,
            filter: .all,
            folderID: nil
        )
        store.applyFolderListAfterDelete(removedID: folderA)
        await VaultPersistedCacheCoordinator.shared.persistVaultPresentation(reason: "test", isRollback: false)
        let item = store.cachedHome(filter: .all, folderID: nil)?.items.first
        XCTAssertEqual(item?.folderIDs, [folderB])
    }

    func testPruneContentReference() async {
        let store = makeStore(viewer: viewerA)
        let ref = VaultContentRef(contentType: .profilePost, contentID: "post-deleted")
        store.seedHome(
            items: [makeItem(id: "vi-post", contentID: "post-deleted", type: .profilePost)],
            folders: [],
            nextCursor: nil,
            filter: .all,
            folderID: nil
        )
        store.pruneContentReference(ref)
        await VaultPersistedCacheCoordinator.shared.persistVaultPresentation(reason: "test", isRollback: false)
        XCTAssertFalse(store.state(for: ref).isVaulted)
        XCTAssertTrue(store.cachedHome(filter: .all, folderID: nil)?.items.isEmpty == true)
    }

    func testRapidSaveRemoveNewestStateWins() async {
        let store = makeStore(viewer: viewerA)
        let ref = VaultContentRef(contentType: .trade, contentID: "race")
        store.seedHome(items: [], folders: [], nextCursor: nil, filter: .all, folderID: nil)
        store.seedHome(
            items: [makeItem(id: "v1", contentID: "race")],
            folders: [],
            nextCursor: nil,
            filter: .all,
            folderID: nil
        )
        await VaultPersistedCacheCoordinator.shared.persistVaultPresentation(reason: "save", isRollback: false)
        store.pruneContentReference(ref)
        await VaultPersistedCacheCoordinator.shared.persistVaultPresentation(reason: "remove", isRollback: false)
        let disk = VaultDiskCache.loadSnapshot(viewerID: viewerA)
        XCTAssertFalse(disk?.states[ref.cacheKey]?.isVaulted == true)
    }

    // MARK: - Helpers

    private func makeStore(viewer: ProfileID) -> VaultStore {
        let store = VaultStore(repository: InMemoryVaultRepository())
        wirePersistence(store: store, viewer: viewer)
        return store
    }

    private func wirePersistence(store: VaultStore, viewer: ProfileID) {
        VaultPersistedCacheCoordinator.shared.configure(
            store: store,
            session: VaultTestSession(viewerID: viewer)
        )
        store.configurePersistence(VaultPersistedCacheCoordinator.shared)
    }

    private func makeFolder(id: String, name: String = "Folder") -> VaultFolder {
        VaultFolder(
            id: VaultFolderID(id),
            name: name,
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func makeItem(
        id: String,
        contentID: String,
        type: VaultContentType = .trade
    ) -> VaultItem {
        VaultItem(
            id: VaultItemID(id),
            ref: VaultContentRef(contentType: type, contentID: contentID),
            createdAt: .now,
            folderIDs: []
        )
    }
}

private struct VaultTestSession: SessionProviding {
    let viewerID: ProfileID
    var currentUserID: UserID? {
        get async { UserID(viewerID.rawValue) }
    }
    var accessToken: String? {
        get async { "test" }
    }
}

private final class InMemoryVaultRepository: VaultRepository, @unchecked Sendable {
    func state(for refs: [VaultContentRef]) async throws -> [VaultContentRef: VaultItemState] { [:] }
    func folders() async throws -> [VaultFolder] { [] }
    func createFolder(name: String) async throws -> VaultFolder {
        VaultFolder(id: VaultFolderID(UUID().uuidString), name: name, createdAt: .now, updatedAt: .now)
    }
    func renameFolder(id: VaultFolderID, name: String) async throws -> VaultFolder {
        VaultFolder(id: id, name: name, createdAt: .now, updatedAt: .now)
    }
    func deleteFolder(id: VaultFolderID) async throws {}
    func saveToVault(ref: VaultContentRef, folderID: VaultFolderID?) async throws -> VaultItem {
        VaultItem(id: VaultItemID(UUID().uuidString), ref: ref, createdAt: .now, folderIDs: folderID.map { [$0] } ?? [])
    }
    func addToFolder(vaultItemID: VaultItemID, folderID: VaultFolderID) async throws {}
    func removeFromFolder(vaultItemID: VaultItemID, folderID: VaultFolderID) async throws {}
    func removeFromVault(vaultItemID: VaultItemID) async throws {}
    func listItems(
        filter: VaultContentFilter,
        folderID: VaultFolderID?,
        cursor: String?,
        limit: Int
    ) async throws -> VaultListPage {
        VaultListPage(items: [], nextCursor: nil)
    }
}

private final class FailingVaultRepository: VaultRepository, @unchecked Sendable {
    var failSave: Bool
    init(failSave: Bool) { self.failSave = failSave }
    func state(for refs: [VaultContentRef]) async throws -> [VaultContentRef: VaultItemState] { [:] }
    func folders() async throws -> [VaultFolder] { [] }
    func createFolder(name: String) async throws -> VaultFolder {
        VaultFolder(id: VaultFolderID("f"), name: name, createdAt: .now, updatedAt: .now)
    }
    func renameFolder(id: VaultFolderID, name: String) async throws -> VaultFolder {
        VaultFolder(id: id, name: name, createdAt: .now, updatedAt: .now)
    }
    func deleteFolder(id: VaultFolderID) async throws {}
    func saveToVault(ref: VaultContentRef, folderID: VaultFolderID?) async throws -> VaultItem {
        if failSave { throw AppError.unknown(message: "fail") }
        return VaultItem(id: VaultItemID("x"), ref: ref, createdAt: .now, folderIDs: [])
    }
    func addToFolder(vaultItemID: VaultItemID, folderID: VaultFolderID) async throws {}
    func removeFromFolder(vaultItemID: VaultItemID, folderID: VaultFolderID) async throws {}
    func removeFromVault(vaultItemID: VaultItemID) async throws {}
    func listItems(
        filter: VaultContentFilter,
        folderID: VaultFolderID?,
        cursor: String?,
        limit: Int
    ) async throws -> VaultListPage {
        VaultListPage(items: [], nextCursor: nil)
    }
}
