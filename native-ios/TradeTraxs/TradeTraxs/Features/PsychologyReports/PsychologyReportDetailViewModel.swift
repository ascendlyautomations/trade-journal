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
    private(set) var aiSummary: String?
    private(set) var isLoadingAI = false

    let reportID: ReportID

    private let psychologyReports: any PsychologyReportRepository
    private let ai: any AIRepository

    init(
        reportID: ReportID,
        psychologyReports: any PsychologyReportRepository,
        ai: any AIRepository
    ) {
        self.reportID = reportID
        self.psychologyReports = psychologyReports
        self.ai = ai
    }

    var title: String { report?.title ?? "Psychology Report" }
    var dateRangeLabel: String? { report?.dateRangeLabel }

    func bootstrapIfNeeded() async {
        guard phase == .idle else { return }
        phase = .loading
        do {
            let loaded = try await psychologyReports.report(for: reportID, forceNetwork: false)
            report = loaded
            if let cached = PsychologyReportSessionStore.shared.cachedAISummary(
                for: reportID,
                factsHash: loaded.factsHash
            ) {
                aiSummary = cached
            }
            phase = .loaded
        } catch {
            phase = .failed(PsychologyReportDetailViewModel.userFacingMessage(for: error))
        }
    }

    func loadAISummaryIfNeeded() async {
        guard let report, aiSummary == nil, !isLoadingAI else { return }
        isLoadingAI = true
        defer { isLoadingAI = false }

        let facts = PsychologyReportFactsBuilder.build(from: report)
        do {
            let response = try await ai.explainPsychologyCoach(
                PsychologyCoachAIRequest(
                    facts: facts,
                    messages: [],
                    mode: .reportSummary
                )
            )
            aiSummary = response.reply
            PsychologyReportSessionStore.shared.applyAISummary(
                response.reply,
                reportID: reportID,
                factsHash: report.factsHash
            )
        } catch {
            aiSummary = nil
        }
    }

    static func userFacingMessage(for error: Error) -> String {
        if let app = error as? AppError {
            return UserFacingError.map(app).message
        }
        return "We couldn't load this psychology report."
    }
}
