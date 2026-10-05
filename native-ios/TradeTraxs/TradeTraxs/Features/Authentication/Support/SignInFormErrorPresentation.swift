import Foundation

/// Inline Sign In / Sign in with Apple copy — never expose raw Supabase or transport strings.
nonisolated enum SignInFormErrorPresentation {
    static let incorrectCredentials = "Incorrect email or password."
    static let genericFailure = "Sign in failed. Please try again."
    static let networkUnavailable =
        "Unable to connect. Check your internet connection and try again."
    static let timedOut = "Sign in timed out. Please try again."
    static let bootstrapIncomplete = "Unable to finish signing in. Please try again."
    static let appleFailure = "Sign in with Apple failed. Please try again."

    /// Machine-readable ``AuthenticationError.unknown`` reasons (not shown to users).
    enum Reason {
        static let networkUnavailable = "sign_in_network_unavailable"
        static let timedOut = "sign_in_timed_out"
        static let serverUnavailable = "sign_in_server_unavailable"
        static let bootstrapIncomplete = "sign_in_bootstrap_incomplete"
        static let sessionNotReady = "sign_in_session_not_ready"
    }

    static func inlineMessage(for error: Error) -> String {
        if let auth = error as? AuthenticationError {
            return inlineMessage(for: auth)
        }
        if let app = error as? AppError {
            return inlineMessage(for: app)
        }
        if let network = error as? NetworkError {
            return inlineMessage(for: network)
        }
        if let url = error as? URLError {
            return inlineMessage(for: url)
        }
        return genericFailure
    }

    static func inlineMessage(for auth: AuthenticationError) -> String {
        switch auth {
        case .invalidCredentials, .invalidEmail, .invalidPassword:
            return incorrectCredentials
        case .cancelled:
            return ""
        case .emailConfirmationRequired, .emailAlreadyRegistered:
            return ""
        case .providerUnavailable(.apple), .providerTokenInvalid(.apple), .providerMisconfigured(.apple):
            return appleFailure
        case .providerUnavailable(.google):
            return "Sign in with Google failed. Please try again."
        case .providerTokenInvalid, .providerMisconfigured, .providerUnavailable:
            return genericFailure
        case .unknown(let reason):
            return message(forUnknownReason: reason)
        case .notConfigured:
            return genericFailure
        case .sessionExpired, .sessionMissing, .refreshFailed, .biometricUnavailable, .biometricFailed,
             .keychain, .validation:
            return genericFailure
        }
    }

    static func inlineMessage(for app: AppError) -> String {
        switch app {
        case .cancelled:
            return ""
        case .transport(let network):
            return inlineMessage(for: network)
        case .authentication(let auth):
            return inlineMessage(for: auth)
        case .unknown:
            return genericFailure
        case .notImplemented:
            return genericFailure
        }
    }

    static func inlineMessage(for network: NetworkError) -> String {
        switch network {
        case .connectivity:
            return networkUnavailable
        case .timeout:
            return timedOut
        case .cancelled:
            return ""
        case .server:
            return genericFailure
        case .unauthorized, .forbidden, .rateLimited, .decoding, .validation, .unknown:
            return genericFailure
        }
    }

    static func inlineMessage(for urlError: URLError) -> String {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return networkUnavailable
        case .timedOut:
            return timedOut
        case .cancelled:
            return ""
        default:
            return networkUnavailable
        }
    }

    private static func message(forUnknownReason reason: String) -> String {
        switch reason {
        case Reason.networkUnavailable:
            return networkUnavailable
        case Reason.timedOut:
            return timedOut
        case Reason.serverUnavailable:
            return genericFailure
        case Reason.bootstrapIncomplete, Reason.sessionNotReady:
            return bootstrapIncomplete
        case "Sign-in finished without an active session.":
            return bootstrapIncomplete
        default:
            return genericFailure
        }
    }
}
