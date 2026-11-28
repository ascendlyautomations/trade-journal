import Foundation
import OSLog

#if DEBUG
nonisolated enum BrokerIntegrationDebugLog {
    private static let log = Logger(subsystem: AppLog.subsystem, category: "BrokerIntegration")

    static func connectionsResponse(status: Int, bytes: Int) {
        log.info("[BrokerIntegration] connections.response status=\(status, privacy: .public) bytes=\(bytes, privacy: .public)")
    }

    static func connectionsDecoded(count: Int) {
        log.info("[BrokerIntegration] connections.decoded count=\(count, privacy: .public)")
    }

    static func connectionsActive(count: Int) {
        log.info("[BrokerIntegration] connections.active count=\(count, privacy: .public)")
    }

    static func connectionRow(idPresent: Bool, status: String, apiEnvironment: String?) {
        log.info("[BrokerIntegration] connection idPresent=\(idPresent, privacy: .public) status=\(status, privacy: .public) apiEnvironment=\(apiEnvironment ?? "-", privacy: .public)")
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

    static func accountsDiscoverySummary(
        state: String,
        connectionStatus: String?,
        forceRefresh: Bool,
        rawAccountsCount: Int?,
        accountsKeyPresent: Bool,
        discoveryOk: Bool?,
        discoveryReason: String?,
        discoveryAccountCount: Int?
    ) {
        let rawCountLabel = rawAccountsCount.map(String.init) ?? "nil"
        let discoveryOkLabel = discoveryOk.map { $0 ? "true" : "false" } ?? "nil"
        let discoveryCountLabel = discoveryAccountCount.map(String.init) ?? "nil"
        log.info(
            "[BrokerIntegration] accounts.summary state=\(state, privacy: .public) connectionStatus=\(connectionStatus ?? "-", privacy: .public) forceRefresh=\(forceRefresh, privacy: .public) rawAccountsCount=\(rawCountLabel, privacy: .public) accountsKeyPresent=\(accountsKeyPresent, privacy: .public) discoveryOk=\(discoveryOkLabel, privacy: .public) discoveryReason=\(discoveryReason ?? "-", privacy: .public) discoveryAccountCount=\(discoveryCountLabel, privacy: .public)"
        )
    }

    static func accountsItemDecodeProbe(expectedRawCount: Int, decodedCount: Int) {
        log.error(
            "[BrokerIntegration] accounts.item_decode_mismatch rawCount=\(expectedRawCount, privacy: .public) decodedCount=\(decodedCount, privacy: .public)"
        )
    }

    static func postConnectDiscoveryPass(
        pass: Int,
        connectedConnections: Int,
        mappedAccounts: Int,
        discoverySettled: Bool
    ) {
        log.info(
            "[BrokerIntegration] postConnect.pass=\(pass, privacy: .public) connected=\(connectedConnections, privacy: .public) mappedAccounts=\(mappedAccounts, privacy: .public) discoverySettled=\(discoverySettled, privacy: .public)"
        )
    }

    static func uiConnections(count: Int) {
        log.info("[BrokerIntegration] ui.connections count=\(count, privacy: .public)")
    }

    static func uiActiveConnections(count active: Int, connected: Int) {
        log.info(
            "[BrokerIntegration] ui.connections active=\(active, privacy: .public) connected=\(connected, privacy: .public)"
        )
    }

    static func tradovateLoadFailed(category: String) {
        log.error("[BrokerIntegration] tradovate.loadFailed category=\(category, privacy: .public)")
    }

    static func decodeFailure(context: String, detail: String) {
        log.error("[BrokerIntegration] decode.failure context=\(context, privacy: .public) detail=\(detail, privacy: .public)")
    }

    static func rithmicConnectCapabilities(
        apiEnvironment: String,
        userConnectEnabled: Bool,
        showConnectUi: Bool
    ) {
        log.info(
            "[BrokerIntegration] rithmic.capabilities apiEnvironment=\(apiEnvironment, privacy: .public) userConnectEnabled=\(userConnectEnabled, privacy: .public) showConnectUi=\(showConnectUi, privacy: .public)"
        )
    }

    static func rithmicConnectTransportFailure(detail: String) {
        log.error("[BrokerIntegration] rithmic.connect transportFailure detail=\(detail, privacy: .public)")
    }

    static func rithmicConnectResponse(
        httpStatus: Int,
        ok: Bool,
        code: String?,
        requestedSystemName: String?,
        responseSystemName: String?,
        loginRpCode: [String]?,
        systemNamesCount: Int?
    ) {
        let codeLabel = code ?? "-"
        let requested = requestedSystemName ?? "-"
        let responseSystem = responseSystemName ?? "-"
        let rpCodes = (loginRpCode ?? []).joined(separator: ",")
        let rpLabel = rpCodes.isEmpty ? "-" : rpCodes
        let systemsCount = systemNamesCount.map(String.init) ?? "-"
        log.info(
            "[BrokerIntegration] rithmic.connect response httpStatus=\(httpStatus, privacy: .public) ok=\(ok, privacy: .public) code=\(codeLabel, privacy: .public) requestedSystem=\(requested, privacy: .public) responseSystem=\(responseSystem, privacy: .public) loginRpCode=\(rpLabel, privacy: .public) systemNamesCount=\(systemsCount, privacy: .public)"
        )
    }

    /// When the HTTP layer throws before returning a body (e.g. legacy callers without non-success acceptance).
    static func rithmicConnectBodyDiscarded(httpStatus: Int?, bodyBytes: Int, loginRpCodePresentInRawJSON: Bool) {
        let statusLabel = httpStatus.map(String.init) ?? "nil"
        log.error(
            "[BrokerIntegration] rithmic.connect body_discarded httpStatus=\(statusLabel, privacy: .public) bodyBytes=\(bodyBytes, privacy: .public) loginRpCodeInJSON=\(loginRpCodePresentInRawJSON ? "true" : "false", privacy: .public)"
        )
    }
}
#else
nonisolated enum BrokerIntegrationDebugLog {
    static func connectionsResponse(status: Int, bytes: Int) {}
    static func connectionsDecoded(count: Int) {}
    static func connectionsActive(count: Int) {}
    static func connectionRow(idPresent: Bool, status: String, apiEnvironment: String?) {}
    static func accountsRequest(connectionIdPresent: Bool) {}
    static func accountsResponse(status: Int, bytes: Int) {}
    static func accountsDecoded(count: Int) {}
    static func accountsDiscoverySummary(
        state: String,
        connectionStatus: String?,
        forceRefresh: Bool,
        rawAccountsCount: Int?,
        accountsKeyPresent: Bool,
        discoveryOk: Bool?,
        discoveryReason: String?,
        discoveryAccountCount: Int?
    ) {}
    static func accountsItemDecodeProbe(expectedRawCount: Int, decodedCount: Int) {}
    static func postConnectDiscoveryPass(
        pass: Int,
        connectedConnections: Int,
        mappedAccounts: Int,
        discoverySettled: Bool
    ) {}
    static func uiConnections(count: Int) {}
    static func uiActiveConnections(count active: Int, connected: Int) {}
    static func tradovateLoadFailed(category: String) {}
    static func decodeFailure(context: String, detail: String) {}
    static func rithmicConnectCapabilities(
        apiEnvironment: String,
        userConnectEnabled: Bool,
        showConnectUi: Bool
    ) {}
    static func rithmicConnectTransportFailure(detail: String) {}
    static func rithmicConnectResponse(
        httpStatus: Int,
        ok: Bool,
        code: String?,
        requestedSystemName: String?,
        responseSystemName: String?,
        loginRpCode: [String]?,
        systemNamesCount: Int?
    ) {}
    static func rithmicConnectBodyDiscarded(httpStatus: Int?, bodyBytes: Int, loginRpCodePresentInRawJSON: Bool) {}
}
#endif
