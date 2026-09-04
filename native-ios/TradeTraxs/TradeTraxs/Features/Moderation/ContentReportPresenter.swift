import Foundation
import Observation

@Observable
@MainActor
final class ContentReportPresenter {
    var activeRequest: ContentReportRequest?

    func present(_ request: ContentReportRequest) {
        activeRequest = request
    }

    func dismiss() {
        activeRequest = nil
    }
}
