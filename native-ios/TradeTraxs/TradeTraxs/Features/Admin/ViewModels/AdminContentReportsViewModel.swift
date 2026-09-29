import Foundation
import Observation

@MainActor
@Observable
final class AdminContentReportsViewModel {
    private let repository: any AdminContentReportsRepository

    var statusFilter: AdminContentReportStatusFilter = .open
    var snapshots: [AdminContentReportSnapshot] = []
    var isLoading = false
    var isLoadingMore = false
    var hasMore = false
    var errorMessage: String?

    private var nextOffset = 0

    init(repository: any AdminContentReportsRepository) {
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
            let page = try await repository.fetchReports(
                status: statusFilter,
                limit: AdminContentReportListQuery.defaultPageSize,
                offset: 0
            )
            snapshots = page.rows.map { AdminContentReportHydration.snapshot(row: $0, enrichment: page.enrichment) }
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
            let page = try await repository.fetchReports(
                status: statusFilter,
                limit: AdminContentReportListQuery.defaultPageSize,
                offset: nextOffset
            )
            let added = page.rows.map { AdminContentReportHydration.snapshot(row: $0, enrichment: page.enrichment) }
            snapshots.append(contentsOf: added)
            hasMore = page.hasMore
            nextOffset += page.rows.count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func emptyTitle() -> String {
        switch statusFilter {
        case .open: return "No open reports"
        case .reviewing: return "No reports in review"
        case .resolved: return "No resolved reports"
        case .dismissed: return "No dismissed reports"
        case .all: return "No reports"
        }
    }
}
