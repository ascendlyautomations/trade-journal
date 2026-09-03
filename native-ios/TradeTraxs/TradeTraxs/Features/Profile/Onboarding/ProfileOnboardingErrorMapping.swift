import Foundation
import OSLog

/// User-facing onboarding errors — avoids masking PostgREST JSON as generic copy.
nonisolated enum ProfileOnboardingErrorMapping {
    static let usernameConflictMessage = "That username is already taken. Try another one."

    static func submitMessage(for error: Error) -> String {
        if ProfileUsernamePolicy.isProfilesUsernameConflict(error) {
            return usernameConflictMessage
        }
        if let network = resolveNetworkError(error) {
            return networkMessage(network, context: "save")
        }
        if let app = error as? AppError {
            return UserFacingError.message(for: app)
        }
        return UserFacingError.message(for: error)
    }

    static func avatarUploadMessage(for error: Error) -> String {
        if let network = resolveNetworkError(error) {
            switch network {
            case .connectivity:
                return "You're offline. Connect and try uploading again."
            case .forbidden, .unauthorized:
                return "Couldn't upload profile picture. Sign in again and retry."
            default:
                return "Couldn't upload profile picture. Try a different photo or continue without one."
            }
        }
        return "Couldn't upload profile picture. Try a different photo or continue without one."
    }

    static func resolveNetworkError(_ error: Error) -> NetworkError? {
        if let network = error as? NetworkError { return network }
        if let app = error as? AppError, case .transport(let network) = app { return network }
        return nil
    }

    private static func networkMessage(_ error: NetworkError, context: String) -> String {
        switch error {
        case .connectivity:
            return "You're offline. Check your connection and try again."
        case .unauthorized:
            return "Your session expired. Sign in again to continue."
        case .forbidden:
            return "Couldn't save your profile. Sign in again and try once more."
        case .validation(_, let message):
            return parsePostgREST(message, context: context)
                ?? "Couldn't save your profile. Please try again."
        case .server(_, let message):
            return parsePostgREST(message, context: context)
                ?? "Something went wrong on our end. Please try again."
        case .decoding:
            return "We saved your changes but couldn't read the response. Pull to refresh or try again."
        default:
            return "Something went wrong. Please try again."
        }
    }

    private static func parsePostgREST(_ raw: String?, context: String) -> String? {
        guard let raw else { return nil }
        let lower = raw.lowercased()
        if lower.contains("23505") && lower.contains("username") {
            return usernameConflictMessage
        }
        if lower.contains("protected profile fields") || lower.contains("protected early access") {
            return "Couldn't save your profile. Contact support if this continues."
        }
        if lower.contains("pgrst116") || lower.contains("0 rows") {
            return context == "save"
                ? "Couldn't update your profile. Sign in again and try once more."
                : nil
        }
        return nil
    }

    #if DEBUG
    static func debugStage(_ stage: String, error: Error) {
        AppLog.application.error(
            "ProfileOnboarding failed stage=\(stage, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
    }
    #else
    static func debugStage(_ stage: String, error: Error) {}
    #endif
}
