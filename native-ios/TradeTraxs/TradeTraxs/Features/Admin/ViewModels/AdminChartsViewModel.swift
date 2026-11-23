import Foundation
import Observation

@MainActor
@Observable
final class AdminChartsViewModel {
    private let repository: any AdminUsageAnalyticsRepository

    var selectedRange: AdminChartsRange = .days30
    var bundle: AdminUsageAnalyticsBundle?
    var productBundle: AdminProductAnalyticsBundle?
    var historicalBundle: AdminHistoricalEngagementBundle?
    var historicalQuery: AdminHistoricalEngagementQuery
    var lifecycleQuery: AdminLifecycleAnalyticsQuery
    var lifecycleBundle: AdminLifecycleAnalyticsBundle?
    var lifecycleErrorMessage: String?
    var isLoading = false
    var errorMessage: String?
    var productErrorMessage: String?
    var historicalErrorMessage: String?

    private var cache: [AdminChartsRange: AdminUsageAnalyticsBundle] = [:]
    private var productCache: [AdminChartsRange: AdminProductAnalyticsBundle] = [:]
    private var historicalCache: [AdminHistoricalEngagementQuery: AdminHistoricalEngagementBundle] = [:]
    /// Ranges that failed with a deterministic error; skip automatic reload until Try Again.
    private var failedRanges: Set<AdminChartsRange> = []
    private var productFailedRanges: Set<AdminChartsRange> = []
    private var historicalFailedQueries: Set<AdminHistoricalEngagementQuery> = []
    private var lifecycleCache: [AdminLifecycleAnalyticsQuery: AdminLifecycleAnalyticsBundle] = [:]
    private var lifecycleFailedQueries: Set<AdminLifecycleAnalyticsQuery> = []
    private var fetchTask: Task<Void, Never>?

    init(repository: any AdminUsageAnalyticsRepository) {
        self.repository = repository
        self.historicalQuery = AdminHistoricalEngagementQueryStore.load()
        self.lifecycleQuery = AdminLifecycleAnalyticsQueryStore.load()
    }

    func load(force: Bool = false) async {
        if force {
            failedRanges.remove(selectedRange)
            productFailedRanges.remove(selectedRange)
            historicalFailedQueries.remove(historicalQuery)
            lifecycleFailedQueries.remove(lifecycleQuery)
        } else if failedRanges.contains(selectedRange),
                  productFailedRanges.contains(selectedRange),
                  historicalFailedQueries.contains(historicalQuery),
                  lifecycleFailedQueries.contains(lifecycleQuery) {
            return
        }

        let range = selectedRange
        let hadLegacyCache = cache[range] != nil
        let hadProductCache = productCache[range] != nil

        if !force, hadLegacyCache {
            bundle = cache[range]
            errorMessage = nil
        }
        if !force, hadProductCache {
            productBundle = productCache[range]
            productErrorMessage = nil
        }
        let historicalQuerySnapshot = historicalQuery
        let lifecycleQuerySnapshot = lifecycleQuery
        let hadHistoricalCache = historicalCache[historicalQuerySnapshot] != nil
        if !force, hadHistoricalCache {
            historicalBundle = historicalCache[historicalQuerySnapshot]
            historicalErrorMessage = nil
        }

        if !force, hadLegacyCache, hadProductCache, hadHistoricalCache {
            historicalBundle = historicalCache[historicalQuerySnapshot]
            historicalErrorMessage = nil
            return
        }

        if historicalQuerySnapshot.preset == .custom,
           AdminHistoricalEngagementQueryStore.validate(historicalQuerySnapshot) != nil,
           hadLegacyCache, hadProductCache {
            historicalBundle = nil
            return
        }

        fetchTask?.cancel()
        let task = Task { @MainActor in
            isLoading = true
            defer { isLoading = false }
            let days = range.rawValue

            if !hadLegacyCache || force {
                if force || !failedRanges.contains(range) {
                    do {
                        let fetched = try await repository.fetchBundle(seriesDays: days)
                        guard !Task.isCancelled, self.selectedRange == range else { return }
                        cache[range] = fetched
                        failedRanges.remove(range)
                        bundle = fetched
                        errorMessage = nil
                    } catch {
                        guard !Task.isCancelled, self.selectedRange == range else { return }
                        failedRanges.insert(range)
                        bundle = nil
                        errorMessage = error.localizedDescription
                    }
                }
            }

            if !hadProductCache || force {
                if force || !productFailedRanges.contains(range) {
                    do {
                        let productDays = min(days, AdminProductAnalyticsDefinition.maxProductSeriesDays)
                        let fetched = try await repository.fetchProductBundle(seriesDays: productDays)
                        guard !Task.isCancelled, self.selectedRange == range else { return }
                        productCache[range] = fetched
                        productFailedRanges.remove(range)
                        productBundle = fetched
                        productErrorMessage = nil
                    } catch {
                        guard !Task.isCancelled, self.selectedRange == range else { return }
                        productFailedRanges.insert(range)
                        productBundle = nil
                        productErrorMessage = error.localizedDescription
                    }
                }
            }

            let hadLifecycleCache = lifecycleCache[lifecycleQuerySnapshot] != nil
            if !force, hadLifecycleCache {
                lifecycleBundle = lifecycleCache[lifecycleQuerySnapshot]
                lifecycleErrorMessage = nil
            }

            if !hadHistoricalCache || force {
                if historicalQuerySnapshot.preset != .custom
                    || AdminHistoricalEngagementQueryStore.validate(historicalQuerySnapshot) == nil {
                    if force || !historicalFailedQueries.contains(historicalQuerySnapshot) {
                        do {
                            let fetched = try await repository.fetchHistoricalBundle(query: historicalQuerySnapshot)
                            guard !Task.isCancelled, self.historicalQuery == historicalQuerySnapshot else { return }
                            historicalCache[historicalQuerySnapshot] = fetched
                            historicalFailedQueries.remove(historicalQuerySnapshot)
                            historicalBundle = fetched
                            historicalErrorMessage = nil
                        } catch {
                            guard !Task.isCancelled, self.historicalQuery == historicalQuerySnapshot else { return }
                            historicalFailedQueries.insert(historicalQuerySnapshot)
                            historicalBundle = nil
                            historicalErrorMessage = error.localizedDescription
                        }
                    }
                }
            }

            if !hadLifecycleCache || force {
                if force || !lifecycleFailedQueries.contains(lifecycleQuerySnapshot) {
                    do {
                        let fetched = try await repository.fetchLifecycleBundle(query: lifecycleQuerySnapshot)
                        guard !Task.isCancelled, self.lifecycleQuery == lifecycleQuerySnapshot else { return }
                        lifecycleCache[lifecycleQuerySnapshot] = fetched
                        lifecycleFailedQueries.remove(lifecycleQuerySnapshot)
                        lifecycleBundle = fetched
                        lifecycleErrorMessage = nil
                    } catch {
                        guard !Task.isCancelled, self.lifecycleQuery == lifecycleQuerySnapshot else { return }
                        lifecycleFailedQueries.insert(lifecycleQuerySnapshot)
                        lifecycleBundle = nil
                        lifecycleErrorMessage = error.localizedDescription
                    }
                }
            }
        }
        fetchTask = task
        await task.value
    }

    func onRangeChanged() async {
        await load(force: false)
    }

    func onHistoricalQueryChanged() async {
        AdminHistoricalEngagementQueryStore.save(historicalQuery)
        await load(force: false)
    }

    func onLifecycleQueryChanged() async {
        AdminLifecycleAnalyticsQueryStore.save(lifecycleQuery)
        await load(force: false)
    }

    var showHistoricalTradingCharts: Bool {
        historicalQuery.activityFilter == .all || historicalQuery.activityFilter == .trading
    }

    var showHistoricalSocialCharts: Bool {
        historicalQuery.activityFilter == .all || historicalQuery.activityFilter == .social
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

    var productOverview: AdminProductOverviewSummary? {
        guard let productBundle else { return nil }
        let overview = productBundle.overview
        return AdminProductOverviewSummary(
            productDau: overview.productDau,
            productWau: overview.productWau,
            productMau: overview.productMau,
            dauMauRatio: overview.dauMauRatio,
            retentionD1: productBundle.retentionD1Rate,
            retentionD7: productBundle.retentionD7Rate,
            retentionD30: productBundle.retentionD30Rate
        )
    }

    var productSeriesClampedNote: String? {
        guard selectedRange.rawValue > AdminProductAnalyticsDefinition.maxProductSeriesDays else { return nil }
        return "Product metrics use the last \(AdminProductAnalyticsDefinition.maxProductSeriesDays) UTC days (RPC limit)."
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

struct AdminProductOverviewSummary: Sendable, Hashable {
    var productDau: Int?
    var productWau: Int?
    var productMau: Int?
    var dauMauRatio: Double?
    var retentionD1: Double?
    var retentionD7: Double?
    var retentionD30: Double?
}