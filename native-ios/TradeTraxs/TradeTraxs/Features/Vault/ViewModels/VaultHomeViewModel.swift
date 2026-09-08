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

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    init(repository: any VaultRepository, navigationCoordinator: NavigationCoordinator) {
        self.repository = repository
        self.navigationCoordinator = navigationCoordinator
    }

    func onAppear(store: VaultStore) {
        Task { await refresh(store: store) }
    }

    func refresh(store: VaultStore) async {
        phase = items.isEmpty ? .loading : phase
        do {
            async let folderLoad = repository.folders()
            async let page = repository.listItems(
                filter: filter,
                folderID: selectedFolderID,
                cursor: nil,
                limit: 30
            )
            folders = try await folderLoad
            let loaded = try await page
            items = loaded.items
            nextCursor = loaded.nextCursor
            phase = .loaded
            await store.refreshFolders()
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
        switch item.ref.contentType {
        case .trade:
            navigationCoordinator.open(.feed(.trade(TradeID(item.ref.contentID))))
        case .profilePost:
            navigationCoordinator.open(.profile(.post(PostID(item.ref.contentID))))
        case .feedPost:
            navigationCoordinator.open(.feed(.post(PostID(item.ref.contentID))))
        case .reel:
            navigationCoordinator.open(.profile(.reel(ReelID(item.ref.contentID))))
        case .achievement:
            navigationCoordinator.open(.profile(.achievement(AchievementID(item.ref.contentID))))
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
            await refresh(store: store)
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
