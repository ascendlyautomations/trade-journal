import Foundation
import Observation

@Observable
@MainActor
final class ContentReportSheetViewModel {
    enum Phase: Equatable {
        case selectingReason
        case submitting
        case succeeded(wasDuplicate: Bool)
        case failed(String)
    }

    let request: ContentReportRequest
    private let repository: any ContentReportRepository

    var selectedReason: ContentReportReason?
    var detailsText = ""
    private(set) var phase: Phase = .selectingReason

    init(request: ContentReportRequest, repository: any ContentReportRepository) {
        self.request = request
        self.repository = repository
    }

    var canSubmit: Bool {
        guard let selectedReason else { return false }
        if selectedReason == .other {
            return !detailsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var showsDetailsField: Bool {
        selectedReason == .other
    }

    func selectReason(_ reason: ContentReportReason) {
        selectedReason = reason
        if reason != .other {
            detailsText = ""
        }
    }

    func retryAfterFailure() {
        phase = .selectingReason
    }

    func submit() async {
        guard let selectedReason, canSubmit, phase != .submitting else { return }
        phase = .submitting
        let details = detailsText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await repository.submit(
                target: request.target,
                reason: selectedReason,
                details: details.isEmpty ? nil : details
            )
            phase = .succeeded(wasDuplicate: result.wasDuplicate)
            ExperienceHaptics.play(.success)
        } catch ContentReportSubmissionError.notAuthenticated {
            phase = .failed("Sign in to submit a report.")
            ExperienceHaptics.play(.error)
        } catch ContentReportSubmissionError.duplicate {
            phase = .succeeded(wasDuplicate: true)
            ExperienceHaptics.play(.success)
        } catch ContentReportSubmissionError.serverMessage(let message) {
            phase = .failed(message)
            ExperienceHaptics.play(.error)
        } catch {
            phase = .failed(UserFacingError.message(for: error))
            ExperienceHaptics.play(.error)
        }
    }
}
