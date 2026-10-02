import Foundation

/// Classifies broker account sync outcomes for UI (reconnect vs retry vs hard failure).
nonisolated enum BrokerSyncFailureResolution: Equatable, Sendable {
    case success
    case noAvailableTradeHistory
    case reconnectRequired
    case retryable
    case importFailed

    static func isNoAvailableTradeHistory(_ response: TradovateAccountSyncResponse) -> Bool {
        if response.resolvedClientCode == "BROKER_NO_AVAILABLE_TRADE_HISTORY" { return true }
        if response.summary.syncOutcome == "no_available_trade_history" { return true }
        if response.summary.errorCode == "broker_no_available_trade_history" { return true }
        return false
    }

    static func from(_ response: TradovateAccountSyncResponse) -> BrokerSyncFailureResolution {
        if response.summary.ok {
            if isNoAvailableTradeHistory(response) { return .noAvailableTradeHistory }
            return .success
        }
        if isSyncInProgress(response) { return .retryable }
        if isReconnectRequired(response) { return .reconnectRequired }
        if isRetryable(response) { return .retryable }
        return .importFailed
    }

    private static let reconnectErrorCodes: Set<String> = [
        "reconnect_required",
        "unauthorized",
        "not_connected",
        "oauth_error",
        "invalid_grant",
        "no_refresh_token",
        "token_expired",
        "access_token_expired",
        "invalid_refresh_token",
        "rithmic_password_required",
    ]

    static func isReconnectRequired(_ response: TradovateAccountSyncResponse) -> Bool {
        if response.resolvedClientCode == "BROKER_RECONNECT_REQUIRED" { return true }
        if response.summary.status == "reconnect_required" { return true }
        if response.failureCategory?.lowercased() == "token_refresh_failure" { return true }
        let summaryCode = response.summary.errorCode?.lowercased()
        if let summaryCode, reconnectErrorCodes.contains(summaryCode) { return true }
        let topCode = response.errorCode?.lowercased()
        if let topCode, reconnectErrorCodes.contains(topCode) { return true }
        return false
    }

    /// BFF broker sync routes return a structured body even on non-2xx HTTP status.
    static func payloadContainsSyncSummary(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return json["summary"] != nil
    }

    static func isSyncInProgress(_ response: TradovateAccountSyncResponse) -> Bool {
        response.resolvedClientCode == "BROKER_SYNC_IN_PROGRESS"
            || response.summary.status == "syncing"
            || response.summary.errorCode == "sync_in_progress"
    }

    static func isRetryable(_ response: TradovateAccountSyncResponse) -> Bool {
        if isSyncInProgress(response) { return true }
        if response.resolvedClientCode == "BROKER_TEMPORARILY_UNAVAILABLE" { return true }
        if response.resolvedClientCode == "BROKER_IMPORT_INCOMPLETE" { return true }
        if response.summary.errorCode == "provider_unavailable" { return true }
        if response.summary.errorCode == "import_incomplete_no_fills" { return true }
        if response.summary.errorCode == "import_partial_no_new_fills" { return true }
        if response.summary.status == "partial" { return true }
        return false
    }

    /// Maps sync resolution to broker import failure UI actions (import sheet + settings retry/reconnect).
    static func importFailureAction(
        for resolution: BrokerSyncFailureResolution,
        response: TradovateAccountSyncResponse
    ) -> BrokerImportFailureKind {
        switch resolution {
        case .success:
            return .dismiss
        case .reconnectRequired:
            return .reconnect
        case .retryable:
            return isSyncInProgress(response) ? .syncInProgress : .retry
        case .importFailed, .noAvailableTradeHistory:
            return .dismiss
        }
    }
}

/// Broker import failure actions shared by ``BrokerImportFlowModel`` and settings import UX.
nonisolated enum BrokerImportFailureKind: Equatable, Sendable {
    case retry
    case syncInProgress
    case reconnect
    case dismiss
}

nonisolated extension TradovateAccountSyncResponse {
    var resolvedClientCode: String? {
        if let code = code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            return code
        }
        return nil
    }
}

nonisolated enum BrokerSyncPresentation {
    static func reconnectRequiredMessage(provider: BrokerIntegrationProvider) -> String {
        switch provider {
        case .tradovate:
            return "Your Tradovate connection needs to be reconnected to continue syncing trades."
        case .rithmic:
            return "Your Rithmic connection needs to be reconnected to continue syncing trades."
        }
    }

    static func temporaryFailureMessage() -> String {
        "Unable to import trades right now."
    }

    static func partialImportMessage() -> String {
        "Import finished, but some Tradovate history may still be missing. Sync again to retry."
    }

    static func noAvailableTradeHistoryTitle() -> String {
        "No trades are currently available to import from Tradovate."
    }

    static func noAvailableTradeHistoryDetail() -> String {
        "Tradovate may only make recent trade history available through the connection. To add older trades, import your Tradovate Performance CSV."
    }

    static func syncInProgressMessage() -> String {
        "Sync already in progress."
    }

    static func reconnectPrimaryActionTitle(provider: BrokerIntegrationProvider) -> String {
        switch provider {
        case .tradovate:
            return "Reconnect Tradovate"
        case .rithmic:
            return "Reconnect to Broker"
        }
    }

    static func importFailureMessage(
        for response: TradovateAccountSyncResponse,
        provider: BrokerIntegrationProvider,
        resolution: BrokerSyncFailureResolution
    ) -> String {
        if resolution == .noAvailableTradeHistory {
            return noAvailableTradeHistoryTitle()
        }
        return message(for: response, provider: provider, resolution: resolution)
    }

    static func message(
        for response: TradovateAccountSyncResponse,
        provider: BrokerIntegrationProvider,
        resolution: BrokerSyncFailureResolution
    ) -> String {
        switch resolution {
        case .success, .noAvailableTradeHistory:
            return ""
        case .reconnectRequired:
            return reconnectRequiredMessage(provider: provider)
        case .retryable:
            if BrokerSyncFailureResolution.isSyncInProgress(response) {
                return syncInProgressMessage()
            }
            if response.resolvedClientCode == "BROKER_IMPORT_INCOMPLETE"
                || response.summary.errorCode == "import_incomplete_no_fills"
                || response.summary.errorCode == "import_partial_no_new_fills"
                || (response.summary.status == "partial" && !response.summary.ok)
            {
                return partialImportMessage()
            }
            return temporaryFailureMessage()
        case .importFailed:
            return "Import did not complete."
        }
    }
}
