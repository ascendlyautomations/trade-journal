import Foundation
import OSLog

#if DEBUG
enum BrokerIntegrationDebugLog {
    private static let log = Logger(subsystem: "com.tradetraxs.TradeTraxs", category: "BrokerIntegration")

    static func connectionsResponse(status: Int, bytes: Int) {
        log.info("[BrokerIntegration] connections.response status=\(status, privacy: .public) bytes=\(bytes, privacy: .public)")
    }

    static func connectionsDecoded(count: Int) {
        log.info("[BrokerIntegration] connections.decoded count=\(count, privacy: .public)")
    }

    static func connectionsActive(count: Int) {
        log.info("[BrokerIntegration] connections.active count=\(count, privacy: .public)")
    }

    static func connectionRow(idPresent: Bool, status: String) {
        log.info("[BrokerIntegration] connection idPresent=\(idPresent, privacy: .public) status=\(status, privacy: .public)")
    }

    static func accountsRequest(connectionIdPresent: Bool) {
        log.info("[BrokerIntegration] accounts.request connectionIdPresent=\(connectionIdPresent, privacy: .public)")
    }

    static func accountsResponse(status: Int, bytes: Int) {
        log.info("[BrokerIntegration] accounts.response status=\(status, privacy: .public) bytes=\(bytes, privacy: .public)")
    }

    static func accountsDecoded(count: Int) {
        log.info("[BrokerIntegration] accounts.decoded count=\(count, privacy: .public)")
    }

    static func uiConnections(count: Int) {
        log.info("[BrokerIntegration] ui.connections count=\(count, privacy: .public)")
    }

    static func decodeFailure(context: String, detail: String) {
        log.error("[BrokerIntegration] decode.failure context=\(context, privacy: .public) detail=\(detail, privacy: .public)")
    }
}
#else
enum BrokerIntegrationDebugLog {
    static func connectionsResponse(status: Int, bytes: Int) {}
    static func connectionsDecoded(count: Int) {}
    static func connectionsActive(count: Int) {}
    static func connectionRow(idPresent: Bool, status: String) {}
    static func accountsRequest(connectionIdPresent: Bool) {}
    static func accountsResponse(status: Int, bytes: Int) {}
    static func accountsDecoded(count: Int) {}
    static func uiConnections(count: Int) {}
    static func decodeFailure(context: String, detail: String) {}
}
#endif
