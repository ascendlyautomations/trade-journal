import Foundation

/// Progressive byte streaming helpers built on ``NetworkClient/bytes(for:)``.
///
/// Used later for large CSV / media without buffering entire bodies in memory.
nonisolated struct StreamingSupport: Sendable {
    private let client: NetworkClientBox

    init(client: NetworkClientBox) {
        self.client = client
    }

    /// Streams response bytes and optionally maps HTTP failures.
    func stream(
        _ request: HTTPRequest,
        errorMapper: NetworkErrorMapper = NetworkErrorMapper()
    ) async throws -> AsyncThrowingStream<UInt8, Error> {
        let (bytes, response) = try await client.bytes(for: request)
        if let error = errorMapper.map(data: nil, response: response, error: nil) {
            throw error
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await byte in bytes {
                        try NetworkTaskCancellation.check()
                        continuation.yield(byte)
                    }
                    continuation.finish()
                } catch {
                    if let cancelled = NetworkTaskCancellation.mapIfCancelled(error) {
                        continuation.finish(throwing: cancelled)
                    } else {
                        continuation.finish(throwing: errorMapper.mapTransport(error))
                    }
                }
            }
        }
    }
}
