#if DEBUG
import Foundation
import OSLog

/// Safe payout-edit timing. Never logs notes or image contents.
nonisolated enum PayoutEditDiagnostics {
    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "PayoutEdit"
    )

    static func open(historyItemID: String, editable: Bool, surface: String) {
        log(
            "payout.edit.open historyItemID=\(historyItemID) editable=\(editable) surface=\(surface)"
        )
    }

    static func saveStarted(entryID: String, accountID: String, image: String) {
        log(
            "payout.edit.save.started entryID=\(entryID) accountID=\(accountID) image=\(image)"
        )
    }

    static func saveCompleted(entryID: String, accountID: String) {
        log("payout.edit.save.completed entryID=\(entryID) accountID=\(accountID)")
    }

    static func saveFailed(entryID: String, accountID: String, error: Error) {
        log(
            "payout.edit.save.failed entryID=\(entryID) accountID=\(accountID) \(failureDetail(error))"
        )
    }

    static func imageWriteName(_ image: PayoutEntryImageWrite) -> String {
        switch image {
        case .unchanged: return "unchanged"
        case .set: return "set"
        case .clear: return "clear"
        }
    }

    private static func log(_ message: String) {
        logger.info("[PayoutEdit] \(message, privacy: .public)")
    }

    private static func failureDetail(_ error: Error) -> String {
        if let app = error as? AppError {
            switch app {
            case .transport(let network):
                return networkDetail(network)
            case .authentication:
                return "httpStatus=401 errorCode=authentication"
            case .cancelled:
                return "httpStatus=none errorCode=cancelled"
            case .notImplemented:
                return "httpStatus=none errorCode=notImplemented"
            case .unknown(let message):
                return "httpStatus=none errorCode=\(codeToken(in: message) ?? "unknown")"
            }
        }
        if let network = error as? NetworkError {
            return networkDetail(network)
        }
        return "httpStatus=none errorCode=untyped"
    }

    private static func networkDetail(_ error: NetworkError) -> String {
        switch error {
        case .connectivity:
            return "httpStatus=none errorCode=connectivity"
        case .timeout:
            return "httpStatus=none errorCode=timeout"
        case .cancelled:
            return "httpStatus=none errorCode=cancelled"
        case .unauthorized:
            return "httpStatus=401 errorCode=unauthorized"
        case .forbidden:
            return "httpStatus=403 errorCode=forbidden"
        case .rateLimited:
            return "httpStatus=429 errorCode=rateLimited"
        case .server(let statusCode, let message):
            return "httpStatus=\(statusCode) errorCode=\(codeToken(in: message ?? "") ?? "server")"
        case .decoding:
            return "httpStatus=none errorCode=decoding"
        case .validation(let statusCode, let message):
            let status = statusCode.map(String.init) ?? "none"
            return "httpStatus=\(status) errorCode=\(codeToken(in: message) ?? "validation")"
        case .unknown(let message):
            return "httpStatus=none errorCode=\(codeToken(in: message) ?? "unknown")"
        }
    }

    /// SQLSTATE / PostgREST codes only. The rest of a server message can echo field values.
    private static func codeToken(in message: String) -> String? {
        for token in ["42501", "23514", "23505", "23502", "PGRST116", "PGRST204"] where message.contains(token) {
            return token
        }
        guard let range = message.range(of: #"PGRST[0-9]+"#, options: .regularExpression) else {
            return nil
        }
        return String(message[range])
    }
}
#else
nonisolated enum PayoutEditDiagnostics {
    static func open(historyItemID: String, editable: Bool, surface: String) {}
    static func saveStarted(entryID: String, accountID: String, image: String) {}
    static func saveCompleted(entryID: String, accountID: String) {}
    static func saveFailed(entryID: String, accountID: String, error: Error) {}
    static func imageWriteName(_ image: PayoutEntryImageWrite) -> String { "" }
}
#endif
