import Foundation

enum BrokerTradovateReconnectImport {
    enum Outcome: Sendable {
        case cancelled
        case oauthFailed(String?)
        /// OAuth finished. The follow-up sync failed before a broker response.
        case syncUnavailable
        case syncCompleted(TradovateAccountSyncResponse)
    }

    enum FailureStage: Sendable {
        case authorization
        case sync
    }

    static func outcomeForThrownFailure(stage: FailureStage, message: String?) -> Outcome {
        switch stage {
        case .authorization:
            return .oauthFailed(message)
        case .sync:
            return .syncUnavailable
        }
    }

    /// Re-authorize an existing Tradovate connection, then retry sync on the same mapping.
    static func reconnectAndSync(
        broker: BrokerIntegrationRepository,
        connectionId: String,
        mappingId: String,
        syncMode: TradovateSyncRequestMode = .preview,
        apiEnvironment: String? = nil
    ) async -> Outcome {
        do {
            let url = try await broker.beginTradovateNativeOAuth(
                reconnectConnectionId: connectionId,
                apiEnvironment: apiEnvironment
            )
            let oauth = await TradovateBrokerOAuthSession.connect(authorizeURL: url)
            switch oauth {
            case .cancelled:
                return .cancelled
            case .error(let reason):
                return .oauthFailed(reason)
            case .success:
                break
            }
        } catch {
            return outcomeForThrownFailure(
                stage: .authorization,
                message: UserFacingError.message(for: error)
            )
        }

        do {
            let response = try await broker.syncTradovateAccount(
                connectionId: connectionId,
                mappingId: mappingId,
                mode: syncMode
            )
            BrokerSyncDebugLog.syncReport(
                provider: .tradovate,
                connectionID: connectionId,
                accountMappingID: mappingId,
                response: response
            )
            return .syncCompleted(response)
        } catch {
            return outcomeForThrownFailure(
                stage: .sync,
                message: UserFacingError.message(for: error)
            )
        }
    }
}
