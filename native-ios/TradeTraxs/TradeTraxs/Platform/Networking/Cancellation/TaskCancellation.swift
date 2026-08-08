import Foundation

/// Helpers for cooperative cancellation of network work.
nonisolated enum NetworkTaskCancellation {
    /// Throws ``NetworkError.cancelled`` if the current task is cancelled.
    static func check() throws {
        try Task.checkCancellation()
    }

    static func mapIfCancelled(_ error: Error) -> NetworkError? {
        if error is CancellationError {
            return .cancelled
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return .cancelled
        }
        return nil
    }
}

/// Token for associating caller-owned cancellation with a request ID.
nonisolated struct NetworkCancellationToken: Sendable {
    let requestID: UUID
    let isCancelled: @Sendable () -> Bool

    init(requestID: UUID = UUID(), isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }) {
        self.requestID = requestID
        self.isCancelled = isCancelled
    }

    func throwIfCancelled() throws {
        if isCancelled() {
            throw NetworkError.cancelled
        }
    }
}
