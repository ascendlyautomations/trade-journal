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

    init(
        reportID: ReportID,
        psychologyReports: any PsychologyReportRepository
    ) {
        self.reportID = reportID
        self.psychologyReports = psychologyReports
    }

    var title: String { report?.title ?? "Psychology Report" }
    var dateRangeLabel: String? { report?.dateRangeLabel }

    func bootstrapIfNeeded() async {
        guard phase == .idle else { return }
        phase = .loading
        do {
            let loaded = try await psychologyReports.report(for: reportID, forceNetwork: false)
            report = loaded
            phase = .loaded
        } catch {
            phase = .failed(PsychologyReportDetailViewModel.userFacingMessage(for: error))
        }
    }

    static func userFacingMessage(for error: Error) -> String {
        if let app = error as? AppError {
            return UserFacingError.map(app).message
        }
        return "We couldn't load this psychology report."
    }
}
