import Foundation
import OSLog

/// Privacy-safe classification of a failed `GET /api/billing/entitlement`.
///
/// Logs the HTTP status and a category only. Never includes tokens, response bodies,
/// user ids, or product identifiers.
struct BillingEntitlementFailureClassification: Equatable, Sendable {
    var category: String
    var httpStatus: String
}

nonisolated enum BillingEntitlementFailureLog {
    static let requestPath = "/api/billing/entitlement"

    private static let logger = Logger(subsystem: AppLog.subsystem, category: "Billing")

    static func classify(_ error: Error) -> BillingEntitlementFailureClassification {
        if let network = error as? NetworkError {
            return classify(network)
        }
        if let app = error as? AppError {
            switch app {
            case .transport(let network):
                return classify(network)
            case .authentication(let auth):
                return classify(auth)
            case .cancelled:
                return BillingEntitlementFailureClassification(category: "cancelled", httpStatus: "none")
            case .notImplemented:
                return BillingEntitlementFailureClassification(category: "unavailable", httpStatus: "none")
            case .unknown:
                return BillingEntitlementFailureClassification(category: "unknown", httpStatus: "none")
            }
        }
        if error is DecodingError {
            return BillingEntitlementFailureClassification(category: "decoding", httpStatus: "none")
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return BillingEntitlementFailureClassification(category: "timeout", httpStatus: "none")
            case .cancelled:
                return BillingEntitlementFailureClassification(category: "cancelled", httpStatus: "none")
            default:
                return BillingEntitlementFailureClassification(category: "connectivity", httpStatus: "none")
            }
        }
        return BillingEntitlementFailureClassification(category: "unknown", httpStatus: "none")
    }

    /// Transport-layer failures are logged before auth mapping collapses 401 and 403.
    /// Plan refresh logs the cases that never reached that request.
    static func logPlanStageIfNeeded(_ error: Error) {
        if let app = error as? AppError {
            switch app {
            case .transport, .authentication:
                return
            default:
                break
            }
        }
        if error is DecodingError {
            return
        }
        log(error, stage: "plan")
    }

    static func log(_ error: Error, stage: String) {
        let classification = classify(error)
        log(stage: stage, category: classification.category, httpStatus: classification.httpStatus)
    }

    static func log(stage: String, category: String, httpStatus: String) {
        logger.error(
            "billing.entitlement.failure stage=\(stage, privacy: .public) category=\(category, privacy: .public) httpStatus=\(httpStatus, privacy: .public)"
        )
    }

    private static func classify(_ network: NetworkError) -> BillingEntitlementFailureClassification {
        switch network {
        case .connectivity:
            return BillingEntitlementFailureClassification(category: "connectivity", httpStatus: "none")
        case .timeout:
            return BillingEntitlementFailureClassification(category: "timeout", httpStatus: "none")
        case .cancelled:
            return BillingEntitlementFailureClassification(category: "cancelled", httpStatus: "none")
        case .unauthorized:
            return BillingEntitlementFailureClassification(category: "unauthorized", httpStatus: "401")
        case .forbidden:
            return BillingEntitlementFailureClassification(category: "forbidden", httpStatus: "403")
        case .rateLimited:
            return BillingEntitlementFailureClassification(category: "rateLimited", httpStatus: "429")
        case .server(let statusCode, _):
            return BillingEntitlementFailureClassification(category: "server", httpStatus: String(statusCode))
        case .decoding:
            return BillingEntitlementFailureClassification(category: "decoding", httpStatus: "none")
        case .validation(let statusCode, _):
            return BillingEntitlementFailureClassification(
                category: "client",
                httpStatus: statusCode.map(String.init) ?? "none"
            )
        case .unknown:
            return BillingEntitlementFailureClassification(category: "unknown", httpStatus: "none")
        }
    }

    private static func classify(_ auth: AuthenticationError) -> BillingEntitlementFailureClassification {
        switch auth {
        case .sessionMissing:
            return BillingEntitlementFailureClassification(category: "sessionMissing", httpStatus: "none")
        case .sessionExpired:
            return BillingEntitlementFailureClassification(category: "sessionExpired", httpStatus: "none")
        default:
            return BillingEntitlementFailureClassification(category: "authentication", httpStatus: "none")
        }
    }
}
