#if DEBUG
import Foundation
import OSLog

nonisolated enum WithdrawalsTrace {
    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "WithdrawalsTrace"
    )

    static func log(_ event: String, detail: String = "") {
        if detail.isEmpty {
            logger.info("[WithdrawalsTrace] event=\(event, privacy: .public)")
        } else {
            logger.info("[WithdrawalsTrace] event=\(event, privacy: .public) \(detail, privacy: .public)")
        }
    }

    static func storeIdentity(_ label: String) {
        let identity = ObjectIdentifier(WithdrawalsHistoryStore.shared)
        log("storeIdentity", detail: "\(label) identity=\(identity)")
    }
}
#else
nonisolated enum WithdrawalsTrace {
    static func log(_ event: String, detail: String = "") {}
    static func storeIdentity(_ label: String) {}
}
#endif
