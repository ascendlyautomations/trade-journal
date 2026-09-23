import Foundation

enum BrokerTradovateReconnectImport {
    enum Outcome: Sendable {
        case cancelled
        case oauthFailed(String?)
        case syncCompleted(TradovateAccountSyncResponse)
    }

    /// Re-authorize an existing Tradovate connection, then retry sync on the same mapping.
    static func reconnectAndSync(
        broker: BrokerIntegrationRepository,
        connectionId: String,
        mappingId: String
    ) async -> Outcome {
        do {
            let url = try await broker.beginTradovateNativeOAuth(reconnectConnectionId: connectionId)
            let oauth = await TradovateBrokerOAuthSession.connect(authorizeURL: url)
            switch oauth {
            case .cancelled:
                return .cancelled
            case .error(let reason):
                return .oauthFailed(reason)
            case .success:
                break
            }
            let response = try await broker.syncTradovateAccount(
                connectionId: connectionId,
                mappingId: mappingId,
                mode: .import
            )
            BrokerSyncDebugLog.syncReport(
                provider: .tradovate,
                connectionID: connectionId,
                accountMappingID: mappingId,
                response: response
            )
            return .syncCompleted(response)
        } catch {
            return .oauthFailed(UserFacingError.message(for: error))
        }
    }
}
