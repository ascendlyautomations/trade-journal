import Foundation

/// Active global upload job — set for the duration of encode/upload work so Storage can report byte progress.
nonisolated enum UploadProgressContext {
    @TaskLocal static var jobID: String?
}

/// Byte-level upload progress relay (Storage POST).
actor UploadProgressRelay {
    static let shared = UploadProgressRelay()

    private var simpleHandlers: [String: @Sendable (Double) -> Void] = [:]

    private struct AggregateState {
        var totalBytes: Int64
        var segments: [String: (totalBytes: Int64, fraction: Double)]
        var handler: @Sendable (Double) -> Void
    }

    private var aggregateStates: [String: AggregateState] = [:]
    private var activeSegment: [String: String] = [:]

    func register(jobID: String, handler: @escaping @Sendable (Double) -> Void) {
        simpleHandlers[jobID] = handler
        aggregateStates.removeValue(forKey: jobID)
        activeSegment.removeValue(forKey: jobID)
    }

    func configureAggregate(
        jobID: String,
        totalBytes: Int64,
        handler: @escaping @Sendable (Double) -> Void
    ) {
        simpleHandlers.removeValue(forKey: jobID)
        aggregateStates[jobID] = AggregateState(totalBytes: max(1, totalBytes), segments: [:], handler: handler)
    }

    func registerSegment(jobID: String, segmentID: String, byteCount: Int64) {
        guard var state = aggregateStates[jobID] else { return }
        state.segments[segmentID] = (max(1, byteCount), 0)
        aggregateStates[jobID] = state
    }

    func setActiveSegment(jobID: String, segmentID: String) {
        activeSegment[jobID] = segmentID
    }

    func unregister(jobID: String) {
        simpleHandlers.removeValue(forKey: jobID)
        aggregateStates.removeValue(forKey: jobID)
        activeSegment.removeValue(forKey: jobID)
    }

    func report(jobID: String, fraction: Double) {
        let clamped = min(1, max(0, fraction))
        if var state = aggregateStates[jobID] {
            if let segmentID = activeSegment[jobID],
               var segment = state.segments[segmentID]
            {
                segment.fraction = clamped
                state.segments[segmentID] = segment
                aggregateStates[jobID] = state
                let uploaded = state.segments.values.reduce(Int64(0)) { partial, item in
                    partial + Int64((Double(item.totalBytes) * item.fraction).rounded(.down))
                }
                let aggregate = Double(uploaded) / Double(state.totalBytes)
                state.handler(min(1, max(0, aggregate)))
            }
            return
        }
        simpleHandlers[jobID]?(clamped)
    }
}
