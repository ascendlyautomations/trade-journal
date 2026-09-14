import Foundation

extension URLSession {
    /// Performs a data task and returns URLSessionTaskMetrics when the session uses a task delegate.
    func dataWithTaskMetrics(
        for request: URLRequest,
        metricsCollector: URLSessionTaskMetricsCollector = .shared
    ) async throws -> (Data, URLResponse, URLSessionTaskMetrics?) {
        try await withCheckedThrowingContinuation { continuation in
            final class TaskIdentifierSlot: @unchecked Sendable {
                var value: Int = 0
            }
            let taskIdentifierSlot = TaskIdentifierSlot()
            let task = dataTask(with: request) { data, response, error in
                let metrics = metricsCollector.consumeMetrics(taskIdentifier: taskIdentifierSlot.value)
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
            taskIdentifierSlot.value = task.taskIdentifier
            task.resume()
        }
    }
}
