import Foundation
import Observation

@Observable
@MainActor
final class ProfileInsightsViewModel {
    enum Phase {
        case idle
        case loading
        case loaded(ProfileInsightsBootstrapV1)
        case failed(String)
    }

    private(set) var selectedScope: ProfileInsightsTimeScope = .preset(.days30)
    private(set) var phase: Phase = .idle
    private(set) var isRefreshing = false

    var showsCustomDateSheet = false
    var draftCustomRangeStart: Date?
    var draftCustomRangeEnd: Date?

    private let repository: ProfileInsightsRepository
    private var loadTask: Task<Void, Never>?

    init(repository: ProfileInsightsRepository) {
        self.repository = repository
    }

    var periodPickerOption: ProfileInsightsPeriodOption {
        switch selectedScope {
        case .preset(let range):
            switch range {
            case .days7: return .days7
            case .days30: return .days30
            case .days90: return .days90
            }
        case .custom:
            return .custom
        }
    }

    var displayedBootstrap: ProfileInsightsBootstrapV1? {
        if case .loaded(let bootstrap) = phase { return bootstrap }
        return nil
    }

    var canApplyCustomDateRange: Bool {
        guard let start = draftCustomRangeStart, let end = draftCustomRangeEnd else { return false }
        return start <= end
    }

    func loadIfNeeded() {
        guard loadTask == nil else { return }
        reload()
    }

    func setPeriodOption(_ option: ProfileInsightsPeriodOption) {
        if option == .custom {
            openCustomDateSheet()
            return
        }
        guard let preset = option.preset else { return }
        setPreset(preset)
    }

    func setPreset(_ range: ProfileInsightsDayRange) {
        let next: ProfileInsightsTimeScope = .preset(range)
        guard selectedScope != next else { return }
        selectedScope = next
        reload()
    }

    func openCustomDateSheet() {
        if case .custom(let interval) = selectedScope {
            draftCustomRangeStart = interval.start
            draftCustomRangeEnd = interval.end
        } else {
            draftCustomRangeStart = Calendar.current.date(byAdding: .day, value: -29, to: Date())
            draftCustomRangeEnd = Date()
        }
        showsCustomDateSheet = true
    }

    func cancelCustomDateSheet() {
        showsCustomDateSheet = false
    }

    func applyCustomDateRange() {
        guard canApplyCustomDateRange,
              let start = draftCustomRangeStart,
              let end = draftCustomRangeEnd
        else { return }
        let interval = DashboardScopeFilterSupport.normalizedCustomInterval(start: start, end: end)
        let next: ProfileInsightsTimeScope = .custom(interval)
        guard selectedScope != next else {
            showsCustomDateSheet = false
            return
        }
        selectedScope = next
        showsCustomDateSheet = false
        reload()
    }

    func reload() {
        let query = ProfileInsightsDateEncoding.query(for: selectedScope)
        loadTask?.cancel()
        let retainsContent = displayedBootstrap != nil
        if !retainsContent {
            phase = .loading
        } else {
            isRefreshing = true
        }
        loadTask = Task {
            defer {
                loadTask = nil
                isRefreshing = false
            }
            do {
                let value = try await repository.loadInsights(query: query)
                guard !Task.isCancelled else { return }
                #if DEBUG
                ProfileInsightsDebugLog.logViewModelSuccess(
                    days: value.meta.days,
                    contractVersion: value.meta.contract_version
                )
                #endif
                phase = .loaded(value)
            } catch {
                guard !Task.isCancelled else { return }
                #if DEBUG
                ProfileInsightsDebugLog.logViewModelFailure(query: query, error: error)
                #endif
                if retainsContent {
                    // Keep prior metrics visible when a range refresh fails.
                } else {
                    phase = .failed(UserFacingError.message(for: error))
                }
            }
        }
    }
}