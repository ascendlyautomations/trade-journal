import Foundation
import OSLog

#if DEBUG
/// Separates client-side transport wall-clock from decode time for bootstrap RPCs.
nonisolated enum RPCTransportTiming {
    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "RPCTransportTiming"
    )

    static func log(
        rpc: String,
        taskStartToHeadersMs: Double?,
        headersToBodyMs: Double?,
        decodeMs: Double?,
        totalMs: Double
    ) {
        let taskStartLabel = taskStartToHeadersMs.map { String(format: "%.1f", $0) } ?? "n/a"
        let headersToBodyLabel = headersToBodyMs.map { String(format: "%.1f", $0) } ?? "n/a"
        let decodeLabel = decodeMs.map { String(format: "%.1f", $0) } ?? "n/a"
        logger.debug(
            """
            [RPCTransportTiming] rpc=\(rpc, privacy: .public) \
            taskStartToHeadersMs=\(taskStartLabel, privacy: .public) \
            headersToBodyMs=\(headersToBodyLabel, privacy: .public) \
            decodeMs=\(decodeLabel, privacy: .public) \
            totalMs=\(String(format: "%.1f", totalMs), privacy: .public)
            """
        )
    }

    static func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        let elapsed = end - start
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
    }
}
#else
nonisolated enum RPCTransportTiming {
    static func log(
        rpc: String,
        taskStartToHeadersMs: Double?,
        headersToBodyMs: Double?,
        decodeMs: Double?,
        totalMs: Double
    ) {
        _ = (rpc, taskStartToHeadersMs, headersToBodyMs, decodeMs, totalMs)
    }

    static func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        _ = (start, end)
        return 0
    }
}
#endif
