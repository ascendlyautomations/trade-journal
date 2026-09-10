import Foundation

#if DEBUG
import os.log

/// DEBUG-only PostgREST / RPC tracing. Search Xcode console for `[DB_REQUEST]`.
enum DatabaseRequestDebugLog {
    static let prefix = "[DB_REQUEST]"

    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "DB-Request"
    )

    private static let lock = NSLock()
    private static var inFlightKeys: Set<String> = []

    static func log(
        feature: String = "unknown",
        operation: String,
        key: String,
        cache: String = "unknown",
        deduped: Bool = false
    ) {
        let line =
            "\(prefix) feature=\(feature) operation=\(operation) key=\(key) "
            + "cache=\(cache) deduped=\(deduped)"
        logger.debug("\(line, privacy: .public)")
        print(line)
    }

    static func begin(operation: String, key: String) -> (deduped: Bool, token: String) {
        let token = "\(operation)|\(key)"
        lock.lock()
        let deduped = inFlightKeys.contains(token)
        inFlightKeys.insert(token)
        lock.unlock()
        return (deduped, token)
    }

    static func end(token: String) {
        lock.lock()
        inFlightKeys.remove(token)
        lock.unlock()
    }

    static func table(_ table: String, query: [URLQueryItem], feature: String = "unknown") {
        let filterKey = query
            .filter { ["conversation_id", "user_id", "id", "room_id"].contains($0.name) }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        let key = filterKey.isEmpty ? table : "\(table):\(filterKey)"
        let snapshot = begin(operation: "table:\(table)", key: key)
        log(
            feature: feature,
            operation: "table:\(table)",
            key: key,
            deduped: snapshot.deduped
        )
        end(token: snapshot.token)
    }

    static func rpc(_ functionName: String, feature: String = "unknown") {
        let snapshot = begin(operation: "rpc:\(functionName)", key: functionName)
        log(
            feature: feature,
            operation: "rpc:\(functionName)",
            key: functionName,
            deduped: snapshot.deduped
        )
        end(token: snapshot.token)
    }

    static func write(
        operation: String,
        target: String,
        reason: String = "unknown",
        actionId: String = "-"
    ) {
        let line =
            "[DB_WRITE] feature=unknown operation=\(operation) target=\(target) "
            + "reason=\(reason) actionId=\(actionId)"
        logger.debug("\(line, privacy: .public)")
        print(line)
    }
}
#else
enum DatabaseRequestDebugLog {
    static func log(
        feature: String = "unknown",
        operation: String,
        key: String,
        cache: String = "unknown",
        deduped: Bool = false
    ) {}

    static func table(_ table: String, query: [URLQueryItem], feature: String = "unknown") {}
    static func rpc(_ functionName: String, feature: String = "unknown") {}
    static func write(
        operation: String,
        target: String,
        reason: String = "unknown",
        actionId: String = "-"
    ) {}
}
#endif
