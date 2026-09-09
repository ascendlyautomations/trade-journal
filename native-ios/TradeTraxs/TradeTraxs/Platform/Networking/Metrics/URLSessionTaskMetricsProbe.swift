import Foundation
import OSLog

#if DEBUG
/// Collects URLSessionTaskMetrics via URLSessionTaskDelegate (Supabase RPC diagnostics).
final class URLSessionTaskMetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = URLSessionTaskMetricsCollector()

    private let lock = NSLock()
    private var metricsByTaskID: [Int: URLSessionTaskMetrics] = [:]

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock()
        metricsByTaskID[task.taskIdentifier] = metrics
        lock.unlock()
    }

    func consumeMetrics(for task: URLSessionTask) -> URLSessionTaskMetrics? {
        consumeMetrics(taskIdentifier: task.taskIdentifier)
    }

    func consumeMetrics(taskIdentifier: Int) -> URLSessionTaskMetrics? {
        lock.lock()
        defer { lock.unlock() }
        return metricsByTaskID.removeValue(forKey: taskIdentifier)
    }
}

nonisolated enum NetworkTaskMetricsProbe {
    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "NetworkTaskMetrics"
    )

    static func logRPCIfPresent(path: String, metrics: URLSessionTaskMetrics?) {
        guard let metrics else { return }
        guard path.contains("/rest/v1/rpc/") else { return }
        let rpc = path.split(separator: "/").last.map(String.init) ?? path

        let transaction = metrics.transactionMetrics.last
        let protocolName = transaction?.networkProtocolName ?? "unknown"
        let reused = transaction?.isReusedConnection ?? false
        let proxy = transaction?.isProxyConnection ?? false
        let fetchType = resourceFetchTypeLabel(transaction?.resourceFetchType)

        let dnsMs = intervalMs(transaction?.domainLookupStartDate, transaction?.domainLookupEndDate)
        let connectMs = intervalMs(transaction?.connectStartDate, transaction?.connectEndDate)
        let tlsMs = intervalMs(transaction?.secureConnectionStartDate, transaction?.secureConnectionEndDate)
        let requestMs = intervalMs(transaction?.requestStartDate, transaction?.requestEndDate)
        let responseWaitMs = intervalMs(transaction?.requestEndDate, transaction?.responseStartDate)
        let requestStartToEndMs = intervalMs(transaction?.fetchStartDate, transaction?.responseEndDate)
        let totalMs = intervalMs(metrics.taskInterval.start, metrics.taskInterval.end)

        logger.debug(
            """
            [NetworkTaskMetrics] rpc=\(rpc, privacy: .public) \
            protocol=\(protocolName, privacy: .public) \
            reusedConnection=\(reused, privacy: .public) \
            proxyConnection=\(proxy, privacy: .public) \
            resourceFetchType=\(fetchType, privacy: .public) \
            dnsMs=\(format(dnsMs), privacy: .public) \
            connectMs=\(format(connectMs), privacy: .public) \
            tlsMs=\(format(tlsMs), privacy: .public) \
            requestMs=\(format(requestMs), privacy: .public) \
            responseWaitMs=\(format(responseWaitMs), privacy: .public) \
            requestStartToEndMs=\(format(requestStartToEndMs), privacy: .public) \
            totalMs=\(format(totalMs), privacy: .public)
            """
        )
    }

    private static func intervalMs(_ start: Date?, _ end: Date?) -> Double? {
        guard let start, let end else { return nil }
        return max(0, end.timeIntervalSince(start) * 1000)
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f", value)
    }

    private static func resourceFetchTypeLabel(_ type: URLSessionTaskMetrics.ResourceFetchType?) -> String {
        guard let type else { return "n/a" }
        switch type {
        case .networkLoad: return "networkLoad"
        case .serverPush: return "serverPush"
        case .localCache: return "localCache"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }
}
#else
final class URLSessionTaskMetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = URLSessionTaskMetricsCollector()
}

nonisolated enum NetworkTaskMetricsProbe {
    static func logRPCIfPresent(path: String, metrics: URLSessionTaskMetrics?) {
        _ = (path, metrics)
    }
}
#endif
