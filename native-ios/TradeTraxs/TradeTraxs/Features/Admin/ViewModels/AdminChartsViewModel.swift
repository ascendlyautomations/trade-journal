import Foundation
import Observation

@MainActor
@Observable
final class AdminChartsViewModel {
    private let repository: any AdminUsageAnalyticsRepository

    var selectedRange: AdminChartsRange = .days30
    var bundle: AdminUsageAnalyticsBundle?
    var isLoading = false
    var errorMessage: String?

    private var cache: [AdminChartsRange: AdminUsageAnalyticsBundle] = [:]
    /// Ranges that failed with a deterministic error; skip automatic reload until Try Again.
    private var failedRanges: Set<AdminChartsRange> = []
    private var fetchTask: Task<Void, Never>?

    init(repository: any AdminUsageAnalyticsRepository) {
        self.repository = repository
    }

    func load(force: Bool = false) async {
        if force {
            failedRanges.remove(selectedRange)
        } else if failedRanges.contains(selectedRange) {
            return
        } else if let cached = cache[selectedRange] {
            bundle = cached
            errorMessage = nil
            return
        }

        fetchTask?.cancel()
        let range = selectedRange
        let task = Task { @MainActor in
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            do {
                let fetched = try await repository.fetchBundle(seriesDays: range.rawValue)
                guard !Task.isCancelled, self.selectedRange == range else { return }
                cache[range] = fetched
                failedRanges.remove(range)
                bundle = fetched
            } catch {
                guard !Task.isCancelled, self.selectedRange == range else { return }
                failedRanges.insert(range)
                bundle = nil
                errorMessage = error.localizedDescription
            }
        }
        fetchTask = task
        await task.value
    }

    func onRangeChanged() async {
        await load(force: false)
    }

    var summary: AdminChartsSummary? {
        guard let bundle else { return nil }
        return AdminChartsSummary(
            latestDailyActiveUsers: AdminUsageAnalyticsMath.latestDayCount(bundle.series.activeUsersPerDay),
            rollingDailyActiveUsers: bundle.dailyActiveUsers,
            newUsersInPeriod: AdminUsageAnalyticsMath.totalCount(bundle.series.usersPerDay),
            tradesInPeriod: AdminUsageAnalyticsMath.totalCount(bundle.series.tradesPerDay),
            postsInPeriod: AdminUsageAnalyticsMath.totalCount(bundle.series.postsPerDay),
            averageTradesPerDay: AdminUsageAnalyticsMath.averagePerDay(bundle.series.tradesPerDay),
            averagePostsPerDay: AdminUsageAnalyticsMath.averagePerDay(bundle.series.postsPerDay)
        )
    }
}

struct AdminChartsSummary: Sendable, Hashable {
    var latestDailyActiveUsers: Int
    var rollingDailyActiveUsers: Int
    var newUsersInPeriod: Int
    var tradesInPeriod: Int
    var postsInPeriod: Int
    var averageTradesPerDay: Double
    var averagePostsPerDay: Double
}
