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

        case .permission(let permission):
            switch permission {
            case .notAuthenticated:
                return .authentication(.sessionMissing)
            case .notOwner:
                return .unknown(message: "You don’t have permission to do that.")
            case .privateProfile:
                return .unknown(message: "This profile is private.")
            case .blocked:
                return .unknown(message: "You can’t interact with this account.")
            case .moderated:
                return .unknown(message: "This content isn’t available.")
            case .message(let message):
                return .unknown(message: Self.sanitizedDomainMessage(message))
            }

        case .notFound:
            return .unknown(message: "We couldn’t find that.")

        case .conflict(let message):
            return .unknown(message: Self.sanitizedDomainMessage(message, fallback: "That action couldn’t be completed."))

        case .subscription(let subscription):
            switch subscription {
            case .proRequired:
                return .unknown(message: "TraxPro is required for this feature.")
            case .trialExpired:
                return .unknown(message: "Your TraxPro trial has ended.")
            case .paymentRequired:
                return .unknown(message: "There’s a billing issue with your subscription.")
            case .planInactive:
                return .unknown(message: "Your subscription isn’t active.")
            case .message(let message):
                return .unknown(message: Self.sanitizedDomainMessage(message))
            }

        case .tradeValidation(let validation):
            return .unknown(message: Self.tradeValidationMessage(validation))

        case .importFailure(let importError):
            return .unknown(message: Self.importFailureMessage(importError))

        case .businessRule(let rule):
            return .unknown(message: Self.businessRuleMessage(rule))
        }
    }

    private static func sanitizedDomainMessage(
        _ message: String,
        fallback: String = "Something went wrong. Please try again."
    ) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func tradeValidationMessage(_ error: TradeValidationError) -> String {
        switch error {
        case .missingSymbol:
            return "Enter a symbol to continue."
        case .invalidQuantity:
            return "Enter a valid quantity."
        case .invalidPrice:
            return "Enter a valid price."
        case .exitBeforeEntry:
            return "Exit time can’t be before entry time."
        case .accountReadOnly:
            return "This trading account is read-only."
        case .accountRequired:
            return "Choose a trading account to continue."
        case .unsupportedMode:
            return "That account mode isn’t supported here."
        case .message(let message):
            return sanitizedDomainMessage(message)
        }
    }

    private static func importFailureMessage(_ error: ImportError) -> String {
        switch error {
        case .unsupportedFormat:
            return "That file format isn’t supported."
        case .emptyFile:
            return "That file looks empty."
        case .rowInvalid(let line, let reason):
            let detail = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "Row \(line) couldn’t be imported."
            }
            return "Row \(line): \(detail)"
        case .partialSuccess(let imported, let failed):
            return "Imported \(imported) trades. \(failed) couldn’t be imported."
        case .message(let message):
            return sanitizedDomainMessage(message)
        }
    }

    private static func businessRuleMessage(_ error: BusinessRuleViolation) -> String {
        switch error {
        case .dailyLimitExceeded(let cap):
            return "You’ve reached today’s limit of \(cap)."
        case .followRequestRequired:
            return "Send a follow request to continue."
        case .contentNotPublic:
            return "This content isn’t public."
        case .roomCapacityExceeded:
            return "This Trade Room is full."
        case .duplicateAction:
            return "That’s already done."
        case .message(let message):
            return sanitizedDomainMessage(message)
        }
    }
}
