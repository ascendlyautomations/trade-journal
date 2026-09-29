import Foundation
import Observation

@MainActor
@Observable
final class AdminSupportTicketsViewModel {
    private let repository: any AdminSupportTicketsRepository

    var queueFilter: AdminSupportTicketQueueFilter = .unviewed
    var snapshots: [AdminSupportTicketSnapshot] = []
    var isLoading = false
    var isLoadingMore = false
    var hasMore = false
    var errorMessage: String?

    private var nextOffset = 0

    init(repository: any AdminSupportTicketsRepository) {
        self.repository = repository
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        nextOffset = 0
        snapshots = []
        hasMore = false
        defer { isLoading = false }
        do {
            let page = try await repository.fetchTickets(
                queue: queueFilter,
                limit: AdminSupportTicketListQuery.defaultPageSize,
                offset: 0
            )
            snapshots = page.rows.map {
                AdminSupportTicketHydration.snapshot(row: $0, profiles: page.profiles)
            }
            hasMore = page.hasMore
            nextOffset = page.rows.count
        } catch {
            snapshots = []
            errorMessage = error.localizedDescription
        }
    }

    func onFilterChanged() async {
        await reload()
    }

    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repository.fetchTickets(
                queue: queueFilter,
                limit: AdminSupportTicketListQuery.defaultPageSize,
                offset: nextOffset
            )
            let added = page.rows.map {
                AdminSupportTicketHydration.snapshot(row: $0, profiles: page.profiles)
            }
            snapshots.append(contentsOf: added)
            hasMore = page.hasMore
            nextOffset += page.rows.count
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
