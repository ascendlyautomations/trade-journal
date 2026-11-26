import Foundation

/// PostgREST / Postgres failures that should not trigger chart overlay retry loops.
nonisolated enum DashboardAnalyticsChartsFailurePolicy {
    private static let premiumAnalyticsRequiredToken = "TRAXPRO_PREMIUM_ANALYTICS_REQUIRED"

    nonisolated static func isPremiumAnalyticsEntitlementDenial(_ error: Error) -> Bool {
        if case BackendV2RPCError.requestValidation(let detail) = error,
           let message = detail.message?.uppercased(),
           message.contains(premiumAnalyticsRequiredToken)
        {
            return true
        }
        if case .feature(.premiumAnalytics) = ProGateReasonParser.reason(from: error) {
            return true
        }
        return false
    }

    nonisolated static func isProEntitlementDenial(_ error: Error) -> Bool {
        if isPremiumAnalyticsEntitlementDenial(error) { return true }
        return ProGateReasonParser.reason(from: error) != nil
    }

    nonisolated static func shouldNotRetry(_ error: Error) -> Bool {
        if isPremiumAnalyticsEntitlementDenial(error) { return true }
        if isProEntitlementDenial(error) { return true }
        let pieces = [
            String(describing: error),
            (error as NSError).localizedDescription,
            (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? "",
        ]
        let text = pieces.joined(separator: " ").lowercased()
        if text.contains("42501") { return true }
        if text.contains("permission denied") { return true }
        if text.contains("not_authenticated") { return true }
        if text.contains("22p02") { return true }
        if text.contains("invalid input syntax for type uuid") { return true }
        return false
    }
}
