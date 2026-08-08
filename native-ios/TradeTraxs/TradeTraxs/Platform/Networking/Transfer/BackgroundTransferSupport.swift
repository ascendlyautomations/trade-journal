import Foundation

/// Background URLSession wiring for large media / CSV transfers.
///
/// Infrastructure only — no product uploads are started here.
final class BackgroundTransferSupport: NSObject, @unchecked Sendable {
    let configuration: NetworkConfiguration
    let sessionIdentifier: String

    private let session: URLSession

    init(
        configuration: NetworkConfiguration,
        sessionIdentifier: String = "com.tradetraxs.ios.background.transfer"
    ) {
        self.configuration = configuration
        self.sessionIdentifier = sessionIdentifier
        let sessionConfiguration = configuration.makeBackgroundURLSessionConfiguration(
            identifier: sessionIdentifier
        )
        self.session = URLSession(configuration: sessionConfiguration)
        super.init()
    }

    /// Creates an upload task description without resume data / product paths.
    func makeBackgroundUploadTask(
        request: URLRequest,
        fromFile fileURL: URL
    ) -> URLSessionUploadTask {
        session.uploadTask(with: request, fromFile: fileURL)
    }

    func makeBackgroundDownloadTask(request: URLRequest) -> URLSessionDownloadTask {
        session.downloadTask(with: request)
    }

    /// Finish events for AppDelegate background session handoff later.
    func handleEventsForBackgroundURLSession(
        completionHandler: @escaping () -> Void
    ) {
        // Future: store completion handler and invoke from URLSessionDelegate.
        completionHandler()
    }
}
