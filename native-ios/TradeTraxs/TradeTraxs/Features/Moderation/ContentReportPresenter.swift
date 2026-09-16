import Foundation
import Observation

@Observable
@MainActor
final class ContentReportPresenter {
    var activeRequest: ContentReportRequest?

    func present(_ request: ContentReportRequest) {
        if ExploreModeSupport.isActive {
            DemoModeAuthGatePresenter.shared.requireAuthentication()
            return
        }
        activeRequest = request
    }

    func dismiss() {
        activeRequest = nil
    }
}
