import Foundation
import Observation

/// Session-scoped Vault state — mirrors ``EngagementStore`` optimistic patterns.
@Observable
@MainActor
final class VaultStore {
    private(set) var states: [VaultContentRef: VaultItemState] = [:]
    private(set) var folders: [VaultFolder] = []
    private(set) var lastConfirmationMessage: String?

    private let repository: any VaultRepository
    private var persistence: (any VaultPersistenceClient)?
    private var loadedRefs: Set<VaultContentRef> = []
    private var requestedRefs: Set<VaultContentRef> = []
    private var pendingRefs: Set<VaultContentRef> = []
    private var inFlightRefs: Set<VaultContentRef> = []
    private var prefetchTask: Task<Void, Never>?
    private var foldersLoaded = false
    private var foldersTask: Task<Void, Never>?

    struct HomeSnapshot {
        var items: [VaultItem]
        var folders: [VaultFolder]
        var nextCursor: String?
        var filter: VaultContentFilter
        var folderID: VaultFolderID?
        var loadedAt: Date
    }

    private var homeSnapshot: HomeSnapshot?
    private static let homeSoftStaleInterval: TimeInterval = 300

    private static let recentFolderKey = "vault.recentFolderID"

    init(repository: any VaultRepository) {
        self.repository = repository
    }

    func configurePersistence(_ client: any VaultPersistenceClient) {
        persistence = client
    }

    func state(for ref: VaultContentRef) -> VaultItemState {
        states[ref] ?? .notVaulted
    }

    func prefetch(_ refs: [VaultContentRef]) {
        let fresh = refs.filter {
            !loadedRefs.contains($0) && !requestedRefs.contains($0)
        }
        guard !fresh.isEmpty else { return }
        requestedRefs.formUnion(fresh)
        pendingRefs.formUnion(fresh)
        pumpPrefetchIfNeeded()
    }

    func loadFoldersIfNeeded() {
        guard !foldersLoaded, foldersTask == nil else { return }
        foldersTask = Task { [weak self] in
            guard let self else { return }
            defer { self.foldersTask = nil }
            do {
                let loaded = try await self.repository.folders()
                self.folders = loaded
                self.foldersLoaded = true
            } catch {
                // Soft-fail — sheet can retry on next open.
            }
        }
    }

    func refreshFolders() async {
        do {
            folders = try await repository.folders()
            foldersLoaded = true
            if var snapshot = homeSnapshot {
                snapshot.folders = folders
                snapshot.loadedAt = .now
                homeSnapshot = snapshot
            }
        } catch {
            ExperienceHaptics.play(.warning)
        }
    }

    func cachedHome(filter: VaultContentFilter, folderID: VaultFolderID?) -> HomeSnapshot? {
        guard let snapshot = homeSnapshot,
              snapshot.filter == filter,
              snapshot.folderID == folderID
        else { return nil }
        return snapshot
    }

    func isHomeSoftStale(filter: VaultContentFilter, folderID: VaultFolderID?, now: Date = .now) -> Bool {
        guard let snapshot = cachedHome(filter: filter, folderID: folderID) else { return true }
        return now.timeIntervalSince(snapshot.loadedAt) > Self.homeSoftStaleInterval
    }

    func seedHome(
        items: [VaultItem],
        folders: [VaultFolder],
        nextCursor: String?,
        filter: VaultContentFilter,
        folderID: VaultFolderID?,
        loadedAt: Date = .now,
        shouldPersist: Bool = true
    ) {
        self.folders = folders
        foldersLoaded = true
        homeSnapshot = HomeSnapshot(
            items: items,
            folders: folders,
            nextCursor: nextCursor,
            filter: filter,
            folderID: folderID,
            loadedAt: loadedAt
        )
        for item in items {
            states[item.ref] = VaultItemState(
                isVaulted: true,
                vaultItemID: item.id,
                folderIDs: item.folderIDs
            )
            loadedRefs.insert(item.ref)
        }
        if shouldPersist {
            Task { await persistence?.persistVaultPresentation(reason: "seedHome", isRollback: false) }
        }
    }

    func invalidateHomeList() {
        homeSnapshot = nil
    }

    func quickSave(_ ref: VaultContentRef) async -> Bool {
        await save(ref, folderID: nil, confirmation: "Added to Vault")
    }

    func save(_ ref: VaultContentRef, folderID: VaultFolderID?, confirmation: String) async -> Bool {
        guard !inFlightRefs.contains(ref) else { return false }
        if ref.contentID.hasPrefix("dev-") {
            applyOptimisticVault(ref: ref, folderID: folderID, provisionalID: VaultItemID("dev-vault-\(ref.contentID)"))
            loadedRefs.insert(ref)
            lastConfirmationMessage = confirmation
            patchHomeForOptimisticSave(ref: ref, folderID: folderID)
            await persistence?.persistVaultPresentation(reason: "saveDev", isRollback: false)
            return true
        }

        let previous = state(for: ref)
        let homeBefore = homeSnapshot
        inFlightRefs.insert(ref)
        defer { inFlightRefs.remove(ref) }

        applyOptimisticVault(ref: ref, folderID: folderID, provisionalID: previous.vaultItemID ?? VaultItemID(UUID().uuidString))
        patchHomeForOptimisticSave(ref: ref, folderID: folderID)
        await persistence?.persistVaultPresentation(reason: "saveOptimistic", isRollback: false)

        do {
            let item = try await repository.saveToVault(ref: ref, folderID: folderID)
            commitSuccessfulMutation(
                ref: ref,
                state: VaultItemState(isVaulted: true, vaultItemID: item.id, folderIDs: item.folderIDs)
            )
            reconcileHomeItem(item)
            if let folderID {
                Self.storeRecentFolderID(folderID)
            }
            lastConfirmationMessage = confirmation
            await persistence?.persistVaultPresentation(reason: "save", isRollback: false)
            return true
        } catch {
            states[ref] = previous
            homeSnapshot = homeBefore
            await persistence?.persistVaultPresentation(reason: "save", isRollback: true)
            ExperienceHaptics.play(.warning)
            return false
        }
    }

    func addToFolder(_ ref: VaultContentRef, folderID: VaultFolderID, folderName: String) async -> Bool {
        guard let vaultItemID = state(for: ref).vaultItemID else {
            return await save(ref, folderID: folderID, confirmation: "Added to \(folderName)")
        }
        guard !inFlightRefs.contains(ref) else { return false }
        inFlightRefs.insert(ref)
        defer { inFlightRefs.remove(ref) }

        let previous = state(for: ref)
        var optimistic = previous
        if !optimistic.folderIDs.contains(folderID) {
            optimistic.folderIDs.append(folderID)
        }
        optimistic.isVaulted = true
        states[ref] = optimistic
        await persistence?.persistVaultPresentation(reason: "addToFolderOptimistic", isRollback: false)

        do {
            try await repository.addToFolder(vaultItemID: vaultItemID, folderID: folderID)
            commitSuccessfulMutation(ref: ref, state: optimistic)
            Self.storeRecentFolderID(folderID)
            lastConfirmationMessage = "Added to \(folderName)"
            await persistence?.persistVaultPresentation(reason: "addToFolder", isRollback: false)
            return true
        } catch {
            states[ref] = previous
            await persistence?.persistVaultPresentation(reason: "addToFolder", isRollback: true)
            ExperienceHaptics.play(.warning)
            return false
        }
    }

    func removeFromFolder(_ ref: VaultContentRef, folderID: VaultFolderID) async -> Bool {
        guard let vaultItemID = state(for: ref).vaultItemID else { return false }
        guard !inFlightRefs.contains(ref) else { return false }
        inFlightRefs.insert(ref)
        defer { inFlightRefs.remove(ref) }

        let previous = state(for: ref)
        let homeBefore = homeSnapshot
        var optimistic = previous
        optimistic.folderIDs.removeAll { $0 == folderID }
        states[ref] = optimistic
        patchHomeRemoveFolderMembership(ref: ref, folderID: folderID)
        await persistence?.persistVaultPresentation(reason: "removeFromFolderOptimistic", isRollback: false)

        do {
            try await repository.removeFromFolder(vaultItemID: vaultItemID, folderID: folderID)
            commitSuccessfulMutation(ref: ref, state: optimistic)
            lastConfirmationMessage = "Removed from folder"
            await persistence?.persistVaultPresentation(reason: "removeFromFolder", isRollback: false)
            return true
        } catch {
            states[ref] = previous
            homeSnapshot = homeBefore
            await persistence?.persistVaultPresentation(reason: "removeFromFolder", isRollback: true)
            ExperienceHaptics.play(.warning)
            return false
        }
    }

    func removeFromVault(_ ref: VaultContentRef) async -> Bool {
        guard let vaultItemID = state(for: ref).vaultItemID else { return false }
        guard !inFlightRefs.contains(ref) else { return false }
        inFlightRefs.insert(ref)
        defer { inFlightRefs.remove(ref) }

        let previous = state(for: ref)
        let homeBefore = homeSnapshot
        states[ref] = .notVaulted
        removeRefFromHome(ref)
        await persistence?.persistVaultPresentation(reason: "removeOptimistic", isRollback: false)

        do {
            try await repository.removeFromVault(vaultItemID: vaultItemID)
            commitSuccessfulMutation(ref: ref, state: .notVaulted)
            lastConfirmationMessage = "Removed from Vault"
            await persistence?.persistVaultPresentation(reason: "remove", isRollback: false)
            return true
        } catch {
            states[ref] = previous
            homeSnapshot = homeBefore
            await persistence?.persistVaultPresentation(reason: "remove", isRollback: true)
            ExperienceHaptics.play(.warning)
            return false
        }
    }

    func createFolder(named rawName: String) async -> VaultFolder? {
        guard let name = VaultSupport.normalizedFolderName(rawName) else { return nil }
        do {
            let folder = try await repository.createFolder(name: name)
            folders.append(folder)
            folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            foldersLoaded = true
            await persistence?.persistVaultPresentation(reason: "createFolder", isRollback: false)
            return folder
        } catch {
            ExperienceHaptics.play(.warning)
            return nil
        }
    }

    func applyFolderListAfterDelete(removedID: VaultFolderID) {
        folders.removeAll { $0.id == removedID }
        for (ref, var state) in states where state.isVaulted {
            state.folderIDs.removeAll { $0 == removedID }
            states[ref] = state
        }
        if var snapshot = homeSnapshot {
            snapshot.folders = folders
            snapshot.items = snapshot.items.map { item in
                var copy = item
                copy.folderIDs.removeAll { $0 == removedID }
                return copy
            }
            homeSnapshot = snapshot
        }
        Task { await persistence?.persistVaultPresentation(reason: "deleteFolder", isRollback: false) }
    }

    func applyRenamedFolder(_ folder: VaultFolder) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index] = folder
        }
        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if var snapshot = homeSnapshot {
            snapshot.folders = folders
            homeSnapshot = snapshot
        }
        Task { await persistence?.persistVaultPresentation(reason: "renameFolder", isRollback: false) }
    }

    func pruneContentReference(_ ref: VaultContentRef) {
        states[ref] = .notVaulted
        removeRefFromHome(ref)
    }

    func makeSnapshotBlob(viewerID: ProfileID, writeGeneration: UInt64) -> VaultDiskCache.SnapshotBlob {
        var homePages: [VaultDiskCache.HomePageRecord] = []
        if let snapshot = homeSnapshot {
            homePages.append(
                VaultDiskCache.HomePageRecord(
                    filter: snapshot.filter,
                    folderID: snapshot.folderID?.rawValue,
                    items: snapshot.items,
                    nextCursor: snapshot.nextCursor,
                    savedAt: snapshot.loadedAt
                )
            )
        }
        let stateMap = Dictionary(uniqueKeysWithValues: states.map { ($0.key.cacheKey, $0.value) })
        return VaultDiskCache.SnapshotBlob(
            viewerID: viewerID.rawValue,
            savedAt: Date(),
            lastAccessedAt: Date(),
            folders: folders,
            states: stateMap,
            homePages: homePages,
            writeGeneration: writeGeneration
        )
    }

    func applyPersistedSnapshot(
        _ blob: VaultDiskCache.SnapshotBlob,
        filter: VaultContentFilter,
        folderID: VaultFolderID?
    ) {
        folders = blob.folders
        foldersLoaded = !blob.folders.isEmpty
        for (key, state) in blob.states {
            guard let ref = ref(fromCacheKey: key) else { continue }
            states[ref] = state
            loadedRefs.insert(ref)
        }
        guard let page = blob.homePages.first(where: {
            $0.filter == filter && $0.folderID == folderID?.rawValue
        }) ?? blob.homePages.first(where: { $0.filter == .all && $0.folderID == nil })
        else { return }
        seedHome(
            items: page.items,
            folders: blob.folders,
            nextCursor: page.nextCursor,
            filter: page.filter,
            folderID: page.folderID.map { VaultFolderID($0) },
            loadedAt: page.savedAt,
            shouldPersist: false
        )
    }

    func recentFolderID() -> VaultFolderID? {
        guard let raw = UserDefaults.standard.string(forKey: Self.recentFolderKey) else { return nil }
        return VaultFolderID(raw)
    }

    func clearConfirmation() {
        lastConfirmationMessage = nil
    }

    func removeAll() {
        prefetchTask?.cancel()
        prefetchTask = nil
        foldersTask?.cancel()
        foldersTask = nil
        states = [:]
        folders = []
        loadedRefs = []
        requestedRefs = []
        pendingRefs = []
        inFlightRefs = []
        foldersLoaded = false
        homeSnapshot = nil
        lastConfirmationMessage = nil
    }

    // MARK: - Private

    private func applyOptimisticVault(
        ref: VaultContentRef,
        folderID: VaultFolderID?,
        provisionalID: VaultItemID
    ) {
        var snap = state(for: ref)
        snap.isVaulted = true
        snap.vaultItemID = snap.vaultItemID ?? provisionalID
        if let folderID, !snap.folderIDs.contains(folderID) {
            snap.folderIDs.append(folderID)
        }
        states[ref] = snap
    }

    private func commitSuccessfulMutation(ref: VaultContentRef, state: VaultItemState) {
        states[ref] = state
        loadedRefs.insert(ref)
        requestedRefs.insert(ref)
    }

    private func applyIncomingState(_ state: VaultItemState, for ref: VaultContentRef) {
        if inFlightRefs.contains(ref), let current = states[ref] {
            var merged = state
            merged.isVaulted = current.isVaulted
            merged.vaultItemID = current.vaultItemID ?? merged.vaultItemID
            merged.folderIDs = current.folderIDs.isEmpty ? merged.folderIDs : current.folderIDs
            states[ref] = merged
        } else {
            states[ref] = state
        }
        loadedRefs.insert(ref)
        requestedRefs.insert(ref)
        pendingRefs.remove(ref)
    }

    private func pumpPrefetchIfNeeded() {
        guard prefetchTask == nil else { return }
        guard !pendingRefs.isEmpty else { return }

        prefetchTask = Task { [weak self] in
            guard let self else { return }
            while !self.pendingRefs.isEmpty {
                let batch = Array(self.pendingRefs)
                self.pendingRefs.removeAll()
                do {
                    let map = try await self.repository.state(for: batch)
                    guard !Task.isCancelled else { return }
                    for ref in batch {
                        let snap = map[ref] ?? .notVaulted
                        self.applyIncomingState(snap, for: ref)
                    }
                } catch {
                    self.requestedRefs.subtract(batch)
                }
            }
            self.prefetchTask = nil
            self.pumpPrefetchIfNeeded()
        }
    }

    private func ref(fromCacheKey key: String) -> VaultContentRef? {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let type = VaultContentType(rawValue: parts[0]) else { return nil }
        return VaultContentRef(contentType: type, contentID: parts[1])
    }

    private func patchHomeForOptimisticSave(ref: VaultContentRef, folderID: VaultFolderID?) {
        guard var snapshot = homeSnapshot else { return }
        let state = self.state(for: ref)
        guard let vaultItemID = state.vaultItemID else { return }
        if let scopedFolder = snapshot.folderID, scopedFolder != folderID { return }
        let item = VaultItem(
            id: vaultItemID,
            ref: ref,
            createdAt: .now,
            folderIDs: state.folderIDs
        )
        if let index = snapshot.items.firstIndex(where: { $0.ref == ref }) {
            snapshot.items[index] = item
        } else if snapshot.filter.matches(ref.contentType) {
            snapshot.items.insert(item, at: 0)
        }
        homeSnapshot = snapshot
    }

    private func patchHomeRemoveFolderMembership(ref: VaultContentRef, folderID: VaultFolderID) {
        guard var snapshot = homeSnapshot else { return }
        if snapshot.folderID == folderID {
            snapshot.items.removeAll { $0.ref == ref }
        } else {
            snapshot.items = snapshot.items.map { item in
                guard item.ref == ref else { return item }
                var copy = item
                copy.folderIDs.removeAll { $0 == folderID }
                return copy
            }
        }
        homeSnapshot = snapshot
    }

    private func removeRefFromHome(_ ref: VaultContentRef) {
        guard var snapshot = homeSnapshot else { return }
        snapshot.items.removeAll { $0.ref == ref }
        homeSnapshot = snapshot
    }

    private func reconcileHomeItem(_ item: VaultItem) {
        guard var snapshot = homeSnapshot else { return }
        if let index = snapshot.items.firstIndex(where: { $0.ref == item.ref }) {
            snapshot.items[index] = item
        }
        homeSnapshot = snapshot
    }

    private static func storeRecentFolderID(_ id: VaultFolderID) {
        UserDefaults.standard.set(id.rawValue, forKey: recentFolderKey)
    }
}
