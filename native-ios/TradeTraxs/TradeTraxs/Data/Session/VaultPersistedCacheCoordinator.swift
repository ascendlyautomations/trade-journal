import Foundation

@MainActor
protocol VaultPersistenceClient: AnyObject {
    func persistVaultPresentation(reason: String, isRollback: Bool) async
}

/// Viewer-scoped Vault disk hydrate + write-through.
@MainActor
final class VaultPersistedCacheCoordinator: VaultPersistenceClient {
    static let shared = VaultPersistedCacheCoordinator()

    private weak var store: VaultStore?
    private var session: (any SessionProviding)?
    private static let diskWriteQueue = DispatchQueue(label: "VaultPersistedCache.disk", qos: .utility)

    func configure(store: VaultStore, session: any SessionProviding) {
        self.store = store
        self.session = session
    }

    // MARK: - Hydrate

    /// Loads disk off the main thread, applies into ``VaultStore`` on MainActor.
    func hydrateIfNeeded(
        store: VaultStore,
        filter: VaultContentFilter,
        folderID: VaultFolderID?
    ) async -> Bool {
        guard let session,
              let viewerID = await session.currentUserID.map({ ProfileID($0.rawValue) })
        else { return false }

        let started = CFAbsoluteTimeGetCurrent()
        let blob = await Task.detached(priority: .userInitiated) {
            VaultDiskCache.loadSnapshot(viewerID: viewerID)
        }.value

        guard let blob else { return false }

        store.applyPersistedSnapshot(blob, filter: filter, folderID: folderID)

        #if DEBUG
        let ageSec = Int(Date().timeIntervalSince(blob.savedAt))
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        let home = blob.homePages.first {
            $0.filter == filter && $0.folderID == folderID?.rawValue
        }
        print(
            """
            [VaultPersistent][Hydrate] viewer=\(viewerID.rawValue) source=disk \
            items=\(home?.items.count ?? 0) folders=\(blob.folders.count) ageSec=\(ageSec) elapsedMs=\(elapsedMs)
            """
        )
        #endif

        return store.cachedHome(filter: filter, folderID: folderID) != nil
    }

    func persistVaultPresentation(reason: String, isRollback: Bool) async {
        guard let store, let session,
              let viewerID = await session.currentUserID.map({ ProfileID($0.rawValue) })
        else { return }

        let started = CFAbsoluteTimeGetCurrent()
        let generation = VaultPersistedCacheGeneration.bump(viewerID: viewerID)
        var blob = store.makeSnapshotBlob(viewerID: viewerID, writeGeneration: generation)
        let existing = await Task.detached(priority: .utility) {
            VaultDiskCache.loadSnapshot(viewerID: viewerID)
        }.value
        if let existing {
            var mergedPages = existing.homePages.filter { existingPage in
                !blob.homePages.contains {
                    $0.filter == existingPage.filter && $0.folderID == existingPage.folderID
                }
            }
            mergedPages.append(contentsOf: blob.homePages)
            blob.homePages = mergedPages
        }

        let saveBlob = blob
        let viewerCopy = viewerID
        if shouldWriteSynchronously {
            Self.diskWriteQueue.sync {
                guard !VaultPersistedCacheGeneration.isStale(viewerID: viewerCopy, generation: generation) else {
                    return
                }
                VaultDiskCache.saveSnapshot(saveBlob)
            }
        } else {
            Self.diskWriteQueue.async {
                guard !VaultPersistedCacheGeneration.isStale(viewerID: viewerCopy, generation: generation) else {
                    return
                }
                VaultDiskCache.saveSnapshot(saveBlob)
            }
        }

        #if DEBUG
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        if isRollback {
            print(
                """
                [VaultPersistent][Rollback] viewer=\(viewerID.rawValue) mutation=\(reason)
                """
            )
        } else {
            print(
                """
                [VaultPersistent][Write] viewer=\(viewerID.rawValue) reason=\(reason) \
                items=\(blob.homePages.reduce(0) { $0 + $1.items.count }) folders=\(blob.folders.count) \
                elapsedMs=\(elapsedMs)
                """
            )
        }
        #else
        _ = isRollback
        _ = reason
        #endif
    }

    static func flushPendingDiskWritesForTesting() {
        Self.diskWriteQueue.sync {}
    }

    static func clearAll() {
        VaultDiskCache.clearAll()
    }

    func pruneContent(_ ref: VaultContentRef) async {
        store?.pruneContentReference(ref)
        await persistVaultPresentation(reason: "contentDeleted", isRollback: false)
    }

    // MARK: - Reconcile telemetry

    func logReconcileAfterNetworkRefresh(items: Int, folders: Int, started: CFAbsoluteTime) async {
        guard let session,
              let viewerID = await session.currentUserID.map({ ProfileID($0.rawValue) })
        else { return }
        Self.logReconcile(
            viewerID: viewerID,
            changed: true,
            items: items,
            folders: folders,
            started: started
        )
    }

    static func logReconcile(
        viewerID: ProfileID,
        changed: Bool,
        items: Int,
        folders: Int,
        started: CFAbsoluteTime
    ) {
        #if DEBUG
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        print(
            """
            [VaultPersistent][Reconcile] viewer=\(viewerID.rawValue) changed=\(changed) \
            items=\(items) folders=\(folders) elapsedMs=\(elapsedMs)
            """
        )
        #else
        _ = viewerID
        _ = changed
        _ = items
        _ = folders
        _ = started
        #endif
    }

    private var shouldWriteSynchronously: Bool {
        if VaultPersistedCacheTestHooks.forceSynchronousDiskWrites { return true }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        return false
    }
}
