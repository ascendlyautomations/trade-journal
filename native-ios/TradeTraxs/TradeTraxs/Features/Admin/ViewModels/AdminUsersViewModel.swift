import Foundation
import Observation

@MainActor
@Observable
final class AdminUsersViewModel {
    private let repository: any AdminUsersRepository

    var searchText = ""
    var bannedFilter: AdminUserBannedFilter = .all
    var rows: [AdminUserSummary] = []
    var total = 0
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?

    private var debouncedSearch = ""
    private var debounceTask: Task<Void, Never>?
    private var loadGeneration = 0

    init(repository: any AdminUsersRepository) {
        self.repository = repository
    }

    var canLoadMore: Bool {
        rows.count < total
    }

    func onSearchChanged() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            debouncedSearch = searchText
            await reload()
        }
    }

    func onFilterChanged() async {
        await reload()
    }

    func reload() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let page = try await repository.fetchDirectory(
                AdminUserDirectoryQuery(
                    search: debouncedSearch,
                    bannedFilter: bannedFilter,
                    proFilter: .all,
                    privacyFilter: .all,
                    limit: AdminUserDirectoryQuery.defaultPageSize,
                    offset: 0
                )
            )
            guard generation == loadGeneration else { return }
            rows = page.rows
            total = page.total
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
            rows = []
            total = 0
        }
        isLoading = false
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        let generation = loadGeneration
        do {
            let page = try await repository.fetchDirectory(
                AdminUserDirectoryQuery(
                    search: debouncedSearch,
                    bannedFilter: bannedFilter,
                    proFilter: .all,
                    privacyFilter: .all,
                    limit: AdminUserDirectoryQuery.defaultPageSize,
                    offset: rows.count
                )
            )
            guard generation == loadGeneration else { return }
            rows.append(contentsOf: page.rows)
            total = max(total, page.total)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingMore = false
    }

    func applyUpdatedUser(_ user: AdminUserSummary) {
        if let index = rows.firstIndex(where: { $0.id == user.id }) {
            rows[index] = user
        }
    }

    func removeUser(id: ProfileID) {
        rows.removeAll { $0.id == id }
        total = max(0, total - 1)
    }
}
