import Foundation

/// Top-level domain failure. Never wraps transport / HTTP / SDK errors.
nonisolated enum DomainError: Error, Sendable, Equatable {
    case tradeValidation(TradeValidationError)
    case importFailure(ImportError)
    case permission(PermissionError)
    case businessRule(BusinessRuleViolation)
    case subscription(SubscriptionError)
    case notFound(entity: String, id: String)
    case conflict(message: String)
    case cancelled
}

nonisolated enum TradeValidationError: Error, Sendable, Equatable {
    case missingSymbol
    case invalidQuantity
    case invalidPrice
    case exitBeforeEntry
    case accountReadOnly
    case accountRequired
    case unsupportedMode
    case message(String)
}

nonisolated enum ImportError: Error, Sendable, Equatable {
    case unsupportedFormat
    case emptyFile
    case rowInvalid(line: Int, reason: String)
    case partialSuccess(imported: Int, failed: Int)
    case message(String)
}

nonisolated enum PermissionError: Error, Sendable, Equatable {
    case notAuthenticated
    case notOwner
    case privateProfile
    case blocked
    case moderated
    case message(String)
}

nonisolated enum BusinessRuleViolation: Error, Sendable, Equatable {
    case dailyLimitExceeded( cap: Int)
    case followRequestRequired
    case contentNotPublic
    case roomCapacityExceeded
    case duplicateAction
    case message(String)
}

nonisolated enum SubscriptionError: Error, Sendable, Equatable {
    case proRequired
    case trialExpired
    case paymentRequired
    case planInactive
    case message(String)
}

extension AppError {
    /// Maps domain failures into the app error surface (no networking leakage).
    static func domain(_ error: DomainError) -> AppError {
        switch error {
        case .cancelled:
            return .cancelled
        default:
            return .unknown(message: String(describing: error))
        }
    }
}
