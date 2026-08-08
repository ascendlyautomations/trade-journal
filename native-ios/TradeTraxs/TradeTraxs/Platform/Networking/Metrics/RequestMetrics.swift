import Foundation

/// Lightweight per-request timing / outcome metrics.
nonisolated struct RequestMetrics: Sendable, Equatable {
    var requestID: UUID
    var method: HTTPMethod
    var path: String
    var host: APIHost
    var startedAt: Date
    var endedAt: Date?
    var statusCode: Int?
    var byteCountSent: Int64
    var byteCountReceived: Int64
    var attempt: Int
    var errorDescription: String?

    var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}

nonisolated protocol RequestMetricsRecording: Sendable {
    func record(_ metrics: RequestMetrics)
}

/// In-memory ring buffer for diagnostics / future analytics export.
actor InMemoryRequestMetricsRecorder {
    private var storage: [RequestMetrics] = []
    private let capacity: Int

    init(capacity: Int = 100) {
        self.capacity = capacity
    }

    func record(_ metrics: RequestMetrics) {
        storage.append(metrics)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
    }

    func snapshot() -> [RequestMetrics] {
        storage
    }
}

/// Non-actor façade so interceptors/clients can record without awaiting everywhere.
nonisolated struct RequestMetricsRecorderBox: RequestMetricsRecording, @unchecked Sendable {
    private let recorder: InMemoryRequestMetricsRecorder

    init(recorder: InMemoryRequestMetricsRecorder) {
        self.recorder = recorder
    }

    func record(_ metrics: RequestMetrics) {
        Task {
            await recorder.record(metrics)
        }
    }
}
