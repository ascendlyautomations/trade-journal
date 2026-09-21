import Foundation

#if DEBUG
import OSLog

/// DEBUG-only correlation for bootstrap RPC intents vs SingleFlight vs HTTP.
enum BootstrapRpcTrace {
    nonisolated enum BootstrapRpcTraceContext {
        @TaskLocal static var intentID: UUID?
        @TaskLocal static var trigger: String?
        @TaskLocal static var rpcName: String?
    }

    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "BootstrapRpcTrace"
    )

    @discardableResult
    static func beginIntent(
        rpc: String,
        trigger: String,
        forceNetwork: Bool
    ) -> UUID {
        let intentID = UUID()
        logger.debug(
            """
            [BootstrapRpc] intent=\(intentID.uuidString, privacy: .public) \
            rpc=\(rpc, privacy: .public) trigger=\(trigger, privacy: .public) \
            forceNetwork=\(forceNetwork, privacy: .public)
            """
        )
        return intentID
    }

    static func recordSingleFlightJoin(intentID: UUID, rpc: String, joinedExisting: Bool, waiterCount: Int) {
        logger.debug(
            """
            [BootstrapRpc] intent=\(intentID.uuidString, privacy: .public) \
            rpc=\(rpc, privacy: .public) singleFlightJoined=\(joinedExisting, privacy: .public) \
            waiterCount=\(waiterCount, privacy: .public)
            """
        )
    }

    static func recordSkippedDuplicate(intentID: UUID, rpc: String, trigger: String, reason: String) {
        logger.debug(
            """
            [BootstrapRpc] intent=\(intentID.uuidString, privacy: .public) \
            rpc=\(rpc, privacy: .public) trigger=\(trigger, privacy: .public) \
            skippedDuplicate reason=\(reason, privacy: .public)
            """
        )
    }

    static func httpWillStart(intentID: UUID, requestID: UUID, rpc: String) {
        logger.debug(
            """
            [BootstrapRpc] intent=\(intentID.uuidString, privacy: .public) \
            requestID=\(requestID.uuidString, privacy: .public) \
            rpc=\(rpc, privacy: .public) httpStart
            """
        )
    }

    static func httpCompleted(intentID: UUID, requestID: UUID, rpc: String, elapsedMs: Double) {
        logger.debug(
            """
            [BootstrapRpc] intent=\(intentID.uuidString, privacy: .public) \
            requestID=\(requestID.uuidString, privacy: .public) \
            rpc=\(rpc, privacy: .public) httpComplete elapsedMs=\(String(format: "%.1f", elapsedMs), privacy: .public)
            """
        )
    }

    static func runWithIntent<T>(
        intentID: UUID,
        trigger: String,
        rpc: String,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await BootstrapRpcTraceContext.$intentID.withValue(intentID) {
            try await BootstrapRpcTraceContext.$trigger.withValue(trigger) {
                try await BootstrapRpcTraceContext.$rpcName.withValue(rpc) {
                    try await operation()
                }
            }
        }
    }

    static func noteTransportAwaitIfPresent() {
        guard let intentID = BootstrapRpcTraceContext.intentID,
              let rpc = BootstrapRpcTraceContext.rpcName
        else { return }
        let requestID = UUID()
        httpWillStart(intentID: intentID, requestID: requestID, rpc: rpc)
    }
}
#else
enum BootstrapRpcTrace {
    nonisolated enum BootstrapRpcTraceContext {
        @TaskLocal static var intentID: UUID?
        @TaskLocal static var trigger: String?
        @TaskLocal static var rpcName: String?
    }

    @discardableResult
    static func beginIntent(rpc: String, trigger: String, forceNetwork: Bool) -> UUID { UUID() }

    static func recordSingleFlightJoin(intentID: UUID, rpc: String, joinedExisting: Bool, waiterCount: Int) {}
    static func recordSkippedDuplicate(intentID: UUID, rpc: String, trigger: String, reason: String) {}
    static func httpWillStart(intentID: UUID, requestID: UUID, rpc: String) {}
    static func httpCompleted(intentID: UUID, requestID: UUID, rpc: String, elapsedMs: Double) {}

    static func runWithIntent<T>(
        intentID: UUID,
        trigger: String,
        rpc: String,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await operation()
    }

    static func noteTransportAwaitIfPresent() {}
}
#endif
