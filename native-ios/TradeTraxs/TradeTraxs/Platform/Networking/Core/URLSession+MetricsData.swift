import Foundation

extension URLSession {
    /// Performs a data task and returns URLSessionTaskMetrics when the session uses a task delegate.
    func dataWithTaskMetrics(
        for request: URLRequest,
        metricsCollector: URLSessionTaskMetricsCollector = .shared
    ) async throws -> (Data, URLResponse, URLSessionTaskMetrics?) {
        try await withCheckedThrowingContinuation { continuation in
            var task: URLSessionDataTask!
            task = dataTask(with: request) { data, response, error in
                let metrics = metricsCollector.consumeMetrics(taskIdentifier: task.taskIdentifier)
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(
                        throwing: URLError(.badServerResponse)
                    )
                    return
                }
                continuation.resume(returning: (data, response, metrics))
            }
            task.resume()
        }
    }
}
