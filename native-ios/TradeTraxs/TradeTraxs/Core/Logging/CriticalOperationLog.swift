import Foundation
import OSLog

/// High-impact production failures — OSLog only (no tokens or trade payloads).
nonisolated enum CriticalOperationLog {
    private static let logger = Logger(subsystem: AppLog.subsystem, category: "CriticalOperation")

    static func failure(
        _ operation: String,
        error: Error,
        context: [String: String] = [:]
    ) {
        let ctx = context.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        logger.error(
            "operation=\(operation, privacy: .public) error=\(String(describing: error), privacy: .public) \(ctx, privacy: .public)"
        )
    }
}
