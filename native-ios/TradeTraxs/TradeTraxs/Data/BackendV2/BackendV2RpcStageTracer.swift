import Foundation
import OSLog

#if DEBUG
/// DEBUG-only staged RPC lifecycle tracing — never logs credentials or response bodies.
nonisolated enum BackendV2RpcStageTracer {
    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "BackendV2.RPC"
    )

    static func begin(_ rpcName: String) -> String {
        let id = UUID().uuidString.prefix(8)
        trace(rpcName, stage: "request.prepared", correlation: String(id))
        return String(id)
    }

    static func trace(
        _ rpcName: String,
        stage: String,
        correlation: String,
        detail: String? = nil
    ) {
        if let detail, !detail.isEmpty {
            logger.debug(
                "[\(correlation, privacy: .public)] \(rpcName, privacy: .public) \(stage, privacy: .public) \(detail, privacy: .public)"
            )
        } else {
            logger.debug(
                "[\(correlation, privacy: .public)] \(rpcName, privacy: .public) \(stage, privacy: .public)"
            )
        }
    }
}
#else
nonisolated enum BackendV2RpcStageTracer {
    static func begin(_ rpcName: String) -> String { "" }
    static func trace(_ rpcName: String, stage: String, correlation: String, detail: String? = nil) {}
}
#endif
