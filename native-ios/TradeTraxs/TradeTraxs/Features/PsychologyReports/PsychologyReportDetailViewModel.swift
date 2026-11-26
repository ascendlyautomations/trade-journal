import Foundation
import Observation

@Observable
@MainActor
final class PsychologyReportDetailViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var report: PsychologyReport?

    let reportID: ReportID

    private let psychologyReports: any PsychologyReportRepository
    private var basePeriodRef: PsychologyReportPeriodRef?
    private(set) var selectedTimeScope: PsychologyReportTimeScope = .preset(.ninetyDays)

    var showsCustomDateSheet = false
    var draftCustomRangeStart: Date?
    var draftCustomRangeEnd: Date?

    private var reloadTask: Task<Void, Never>?

    init(
        reportID: ReportID,
        psychologyReports: any PsychologyReportRepository
    ) {
        self.reportID = reportID
        self.psychologyReports = psychologyReports
        self.basePeriodRef = PsychologyReportPeriodRef.parse(reportID: reportID)
        if let basePeriodRef, !basePeriodRef.template.isPeriodic {
            selectedTimeScope = PsychologyReportTimeScope.from(periodID: basePeriodRef.periodID)
        }
    }

    var title: String { report?.title ?? "Psychology Report" }
    var dateRangeLabel: String? { report?.dateRangeLabel }

    /// Weekly / monthly / custom — date range only in the nav bar (performance report pattern).
    var navigationPeriodLabel: String? {
        guard let template = basePeriodRef?.template else { return nil }
        if template.isPeriodic || template == .custom {
            return report?.dateRangeLabel ?? dateRangeLabel
        }
        return nil
    }

    var supportsDateScope: Bool {
        guard let template = basePeriodRef?.template else { return false }
        return !template.isPeriodic && template != .custom
    }

    var timeScopeMenuTitle: String { selectedTimeScope.menuTitle }

    var canApplyCustomDateRange: Bool {
        guard let start = draftCustomRangeStart, let end = draftCustomRangeEnd else { return false }
        return start <= end
    }

    func bootstrapIfNeeded() async {
        guard phase == .idle else { return }
        await loadReport(initial: true)
    }

    func selectPreset(_ preset: PsychologyReportTimePreset) {
        guard supportsDateScope else { return }
        selectedTimeScope = .preset(preset)
        Task { await loadReport(initial: false) }
    }

    func openCustomDateSheet() {
        draftCustomRangeStart = customInterval?.start
            ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())
        draftCustomRangeEnd = customInterval?.end ?? Date()
        showsCustomDateSheet = true
    }

    func applyCustomDateRange() {
        guard canApplyCustomDateRange,
              let start = draftCustomRangeStart,
              let end = draftCustomRangeEnd
        else { return }
        let calendar = TradingReportPeriods.eastern
        let interval = DashboardScopeFilterSupport.normalizedCustomInterval(
            start: start,
            end: end,
            calendar: calendar
        )
        selectedTimeScope = .custom(interval)
        showsCustomDateSheet = false
        Task { await loadReport(initial: false) }
    }

    private var customInterval: DateInterval? {
        if case .custom(let interval) = selectedTimeScope { return interval }
        return nil
    }

    private func loadReport(initial: Bool) async {
        reloadTask?.cancel()
        let task = Task {
            phase = .loading
            do {
                let loaded: PsychologyReport
                if let basePeriodRef {
                    if basePeriodRef.template == .custom {
                        let periodRef = activePeriodRef() ?? basePeriodRef
                        loaded = try await psychologyReports.generateReport(
                            periodRef: periodRef,
                            forceNetwork: false
                        )
                    } else if !basePeriodRef.template.isPeriodic,
                              let periodRef = activePeriodRef() {
                        loaded = try await psychologyReports.generateReport(
                            periodRef: periodRef,
                            forceNetwork: false
                        )
                    } else {
                        loaded = try await psychologyReports.report(for: reportID, forceNetwork: false)
                    }
                } else {
                    loaded = try await psychologyReports.report(for: reportID, forceNetwork: false)
                }
                guard !Task.isCancelled else { return }
                report = loaded
                phase = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(PsychologyReportDetailViewModel.userFacingMessage(for: error))
            }
        }
        reloadTask = task
        await task.value
    }

    private func activePeriodRef() -> PsychologyReportPeriodRef? {
        guard var base = basePeriodRef, !base.template.isPeriodic else { return nil }
        base.periodID = selectedTimeScope.periodID
        return base
    }

    static func userFacingMessage(for error: Error) -> String {
        if let app = error as? AppError {
            return UserFacingError.map(app).message
        }
        return "We couldn't load this psychology report."
    }
}