import Foundation

/// Classifies broker account sync outcomes for UI (reconnect vs retry vs hard failure).
enum BrokerSyncFailureResolution: Equatable, Sendable {
    case success
    case reconnectRequired
    case retryable
    case importFailed

    static func from(_ response: TradovateAccountSyncResponse) -> BrokerSyncFailureResolution {
        if response.summary.ok { return .success }
        if isSyncInProgress(response) { return .retryable }
        if isReconnectRequired(response) { return .reconnectRequired }
        if isRetryable(response) { return .retryable }
        return .importFailed
    }

    static func isReconnectRequired(_ response: TradovateAccountSyncResponse) -> Bool {
        if response.resolvedClientCode == "BROKER_RECONNECT_REQUIRED" { return true }
        if response.summary.status == "reconnect_required" { return true }
        let summaryCode = response.summary.errorCode?.lowercased()
        if summaryCode == "reconnect_required"
            || summaryCode == "unauthorized"
            || summaryCode == "not_connected"
        {
            return true
        }
        let topCode = response.errorCode?.lowercased()
        if topCode == "reconnect_required"
            || topCode == "unauthorized"
            || topCode == "not_connected"
        {
            return true
        }
        return false
    }

    static func isSyncInProgress(_ response: TradovateAccountSyncResponse) -> Bool {
        response.resolvedClientCode == "BROKER_SYNC_IN_PROGRESS"
            || response.summary.status == "syncing"
            || response.summary.errorCode == "sync_in_progress"
    }

    static func isRetryable(_ response: TradovateAccountSyncResponse) -> Bool {
        if isSyncInProgress(response) { return true }
        if response.resolvedClientCode == "BROKER_TEMPORARILY_UNAVAILABLE" { return true }
        if response.summary.errorCode == "provider_unavailable" { return true }
        return false
    }
}

extension TradovateAccountSyncResponse {
    var resolvedClientCode: String? {
        if let code = code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            return code
        }
        return nil
    }
}

enum BrokerSyncPresentation {
    static func reconnectRequiredMessage(provider: BrokerIntegrationProvider) -> String {
        switch provider {
        case .tradovate:
            return "Tradovate needs to be reconnected to continue syncing your trades."
        case .rithmic:
            return "Rithmic needs to be reconnected to continue syncing your trades."
        }
    }

    static func reconnectPrimaryActionTitle() -> String {
        "Reconnect Account"
    }

    static func message(
        for response: TradovateAccountSyncResponse,
        provider: BrokerIntegrationProvider,
        resolution: BrokerSyncFailureResolution
    ) -> String {
        switch resolution {
        case .success:
            return ""
        case .reconnectRequired:
            if let detail = response.summary.error?.trimmingCharacters(in: .whitespacesAndNewlines),
               !detail.isEmpty,
               detail.lowercased().contains("reconnect")
            {
                return detail
            }
            return reconnectRequiredMessage(provider: provider)
        case .retryable:
            if let detail = response.summary.error?.trimmingCharacters(in: .whitespacesAndNewlines),
               !detail.isEmpty
            {
                return detail
            }
            return "Broker sync is temporarily unavailable. Try again in a moment."
        case .importFailed:
            if let detail = response.summary.error?.trimmingCharacters(in: .whitespacesAndNewlines),
               !detail.isEmpty
            {
                return detail
            }
            return "Import did not complete."
        }
    }
}
