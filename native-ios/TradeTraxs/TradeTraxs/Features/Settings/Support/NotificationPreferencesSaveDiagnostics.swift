import Foundation
import OSLog

/// PostgREST / Supabase failures when persisting notification preferences.
nonisolated enum NotificationPreferencesSaveDiagnostics {
    private static let logger = Logger(subsystem: "com.tradetraxs.app", category: "NotificationPreferences")

    static func logLoadFailure(_ error: Error) {
        let detail = describe(error)
        logger.error("notification_preferences load failed \(detail, privacy: .public)")
#if DEBUG
        print("[NotificationPreferences] load failed: \(detail)")
#endif
    }

    static func logSaveFailure(_ error: Error, patch: [NotificationPreferenceKey: Bool]) {
        let keys = patch.keys.map(\.rawValue).sorted().joined(separator: ",")
        let detail = describe(error)
        logger.error(
            "notification_preferences upsert failed keys=[\(keys, privacy: .public)] \(detail, privacy: .public)"
        )
#if DEBUG
        print("[NotificationPreferences] upsert failed keys=[\(keys)]: \(detail)")
#endif
    }

    static func userSaveMessage(for error: Error) -> String {
        _ = describe(error)
        return "Couldn't save notification settings. Your changes were reverted."
    }

    private static func describe(_ error: Error) -> String {
        if let network = error as? NetworkError {
            return describeNetwork(network)
        }
        if case .transport(let underlying) = error as? AppError {
            return describeNetwork(underlying)
        }
        if let app = error as? AppError, case .unknown(let message) = app, !message.isEmpty {
            return message
        }
        return error.localizedDescription
    }

    private static func describeNetwork(_ error: NetworkError) -> String {
        switch error {
        case .server(let code, let message):
            let body = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let codeToken = postgrestCode(from: body)
            if let codeToken {
                return "HTTP \(code) \(codeToken)"
            }
            if !body.isEmpty {
                return "HTTP \(code) \(truncate(body))"
            }
            return "HTTP \(code)"
        case .forbidden:
            return "HTTP 403 forbidden"
        case .unauthorized:
            return "HTTP 401 unauthorized"
        case .decoding(let message):
            return "decode \(truncate(message))"
        case .validation(let code, let message):
            if let code {
                return "HTTP \(code) \(truncate(message))"
            }
            return truncate(message)
        case .connectivity:
            return "offline"
        case .timeout:
            return "timeout"
        case .cancelled:
            return "cancelled"
        case .rateLimited:
            return "rate limited"
        case .unknown(let message):
            return truncate(message)
        }
    }

    private static func postgrestCode(from body: String) -> String? {
        guard body.hasPrefix("{") else { return nil }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let code = json["code"] as? String, !code.isEmpty {
            return code
        }
        return nil
    }

    private static func truncate(_ value: String, max: Int = 120) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        return String(trimmed.prefix(max)) + "…"
    }
}