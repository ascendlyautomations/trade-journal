import Foundation
import Observation

@Observable
@MainActor
final class VaultHomeViewModel {
    private(set) var folders: [VaultFolder] = []
    private(set) var items: [VaultItem] = []
    private(set) var phase: Phase = .idle
    private(set) var nextCursor: String?
    private(set) var isLoadingMore = false

    var filter: VaultContentFilter = .all
    var selectedFolderID: VaultFolderID?

    private let repository: any VaultRepository
    private let navigationCoordinator: NavigationCoordinator
    private let detailCache: DetailPresentationCache
    private let sharedContentContext: SharedContentHydrator.Context
    private let achievements: any AchievementRepository

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    init(
        repository: any VaultRepository,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache,
        sharedContentContext: SharedContentHydrator.Context,
        achievements: any AchievementRepository
    ) {
        self.repository = repository
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        self.sharedContentContext = sharedContentContext
        self.achievements = achievements
    }

    func onAppear(store: VaultStore) {
        let renderStarted = CFAbsoluteTimeGetCurrent()
        if let cached = store.cachedHome(filter: filter, folderID: selectedFolderID) {
            applyCachedHome(cached, renderStarted: renderStarted, store: store)
            return
        }
        Task {
            let hydrated = await VaultPersistedCacheCoordinator.shared.hydrateIfNeeded(
                store: store,
                filter: filter,
                folderID: selectedFolderID
            )
            if hydrated, let cached = store.cachedHome(filter: filter, folderID: selectedFolderID) {
                applyCachedHome(cached, renderStarted: renderStarted, store: store)
                return
            }
            await refresh(store: store, reason: "cold")
        }
    }

    private func applyCachedHome(_ cached: VaultStore.HomeSnapshot, renderStarted: CFAbsoluteTime, store: VaultStore) {
        items = cached.items
        folders = cached.folders
        nextCursor = cached.nextCursor
        phase = .loaded
        VaultLoadDiagnostics.logCacheHit(items: cached.items.count, folders: cached.folders.count)
        VaultLoadDiagnostics.logFirstRenderable(
            dtMs: Int((CFAbsoluteTimeGetCurrent() - renderStarted) * 1000)
        )
        if store.isHomeSoftStale(filter: filter, folderID: selectedFolderID) {
            Task { await refresh(store: store, reason: "softStale") }
        }
    }

    func refresh(store: VaultStore, reason: String = "explicit") async {
        VaultLoadDiagnostics.logRefresh(reason: reason)
        let renderStarted = CFAbsoluteTimeGetCurrent()
        let hadItems = !items.isEmpty
        if !hadItems {
            phase = .loading
        }
        do {
            async let folderLoad = repository.folders()
            async let page = repository.listItems(
                filter: filter,
                folderID: selectedFolderID,
                cursor: nil,
                limit: 30
            )
            let loadedFolders = try await folderLoad
            let loaded = try await page
            items = loaded.items
            folders = loadedFolders
            nextCursor = loaded.nextCursor
            phase = .loaded
            store.seedHome(
                items: loaded.items,
                folders: loadedFolders,
                nextCursor: loaded.nextCursor,
                filter: filter,
                folderID: selectedFolderID
            )
            if !hadItems {
                VaultLoadDiagnostics.logFirstRenderable(
                    dtMs: Int((CFAbsoluteTimeGetCurrent() - renderStarted) * 1000)
                )
            }
            await VaultPersistedCacheCoordinator.shared.logReconcileAfterNetworkRefresh(
                items: loaded.items.count,
                folders: loadedFolders.count,
                started: renderStarted
            )
        } catch {
            if items.isEmpty {
                phase = .failed(FeedSupport.message(for: error))
            }
        }
    }

    func selectFilter(_ filter: VaultContentFilter) {
        guard self.filter != filter || selectedFolderID != nil else { return }
        self.filter = filter
        selectedFolderID = nil
        items = []
        nextCursor = nil
        phase = .loading
    }

    func selectFolder(_ folder: VaultFolder?) {
        selectedFolderID = folder?.id
        items = []
        nextCursor = nil
        phase = .loading
    }

    func loadMoreIfNeeded(currentID: VaultItemID) async {
        guard !isLoadingMore, let nextCursor, !nextCursor.isEmpty else { return }
        guard items.last?.id == currentID else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repository.listItems(
                filter: filter,
                folderID: selectedFolderID,
                cursor: nextCursor,
                limit: 30
            )
            let existing = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            self.nextCursor = page.nextCursor
        } catch {
            // Keep visible items; pagination can retry on pull-to-refresh.
        }
    }

    func open(_ item: VaultItem) {
        ExperienceHaptics.play(.selection)
        Task { await openAsync(item) }
    }

    private func openAsync(_ item: VaultItem) async {
        switch item.ref.contentType {
        case .trade:
            let tradeID = TradeID(item.ref.contentID)
            let reference = SharedContentReference.trade(tradeID)
            _ = await SharedContentHydrator.hydrateForOpen(
                reference: reference,
                context: sharedContentContext,
                surface: .vault
            )
            if let summary = detailCache.tradeSummary(id: tradeID) {
                detailCache.seedPresentationSeed(summary)
            } else if let preview = detailCache.previewTrade(id: tradeID) {
                detailCache.ensurePresentationSeed(forPreview: preview)
            }
            #if DEBUG
            SharedTradeOpenDiagnostics.tapped(tradeID: tradeID)
            #endif
            navigationCoordinator.pushSocialTrade(tradeID, cache: detailCache)
        case .profilePost, .feedPost:
            guard let reference = item.ref.sharedContentReference else { return }
            await SharedContentNavigation.openAsync(
                reference: reference,
                cache: detailCache,
                coordinator: navigationCoordinator,
                hydrationContext: sharedContentContext,
                hydrationSurface: .vault
            )
        case .reel:
            let reference = SharedContentReference.reel(ReelID(item.ref.contentID))
            await SharedContentNavigation.openAsync(
                reference: reference,
                cache: detailCache,
                coordinator: navigationCoordinator,
                hydrationContext: sharedContentContext,
                hydrationSurface: .vault
            )
        case .achievement:
            let achievementID = AchievementID(item.ref.contentID)
            if detailCache.achievement(id: achievementID) == nil {
                if let loaded = try? await achievements.achievement(id: achievementID) {
                    detailCache.seed(loaded)
                }
            }
            navigationCoordinator.pushAchievementDetail(achievementID)
        }
    }

    func createFolder(named name: String, store: VaultStore) async {
        _ = await store.createFolder(named: name)
        folders = store.folders
    }

    func deleteFolder(_ folder: VaultFolder, store: VaultStore) async {
        do {
            try await repository.deleteFolder(id: folder.id)
            folders.removeAll { $0.id == folder.id }
            if selectedFolderID == folder.id {
                selectedFolderID = nil
            }
            store.applyFolderListAfterDelete(removedID: folder.id)
            await refresh(store: store, reason: "folderDeleted")
        } catch {
            ExperienceHaptics.play(.warning)
        }
    }

    func renameFolder(_ folder: VaultFolder, to rawName: String, store: VaultStore) async -> String? {
        guard let normalized = VaultSupport.normalizedFolderName(rawName) else {
            return "Folder name cannot be empty."
        }
        guard normalized != folder.name else { return nil }

        do {
            let updated = try await repository.renameFolder(id: folder.id, name: normalized)
            if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[index] = updated
            }
            folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            store.applyRenamedFolder(updated)
            await store.refreshFolders()
            return nil
        } catch let error as AppError {
            ExperienceHaptics.play(.warning)
            if case .unknown(let message) = error {
                return message
            }
            return FeedSupport.message(for: error)
        } catch {
            ExperienceHaptics.play(.warning)
            return FeedSupport.message(for: error)
        }
    }
}
