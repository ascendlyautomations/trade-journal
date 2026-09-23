import Foundation

/// Which Supabase auth HTTP calls may run while authenticated app networking is torn down.
nonisolated enum AuthNetworkPolicy {
    /// GoTrue endpoints that establish or revoke credentials — not authenticated REST/RPC.
    static func allowsDuringAuthenticatedSessionEnd(path: String, method: HTTPMethod) -> Bool {
        guard path.hasPrefix("/auth/v1/") else { return false }
        switch method {
        case .post:
            if path == "/auth/v1/token" { return true }
            if path == "/auth/v1/logout" { return true }
            if path == "/auth/v1/signup" { return true }
            if path == "/auth/v1/recover" { return true }
            if path == "/auth/v1/resend" { return true }
            return false
        case .put:
            return path == "/auth/v1/user"
        default:
            return false
        }
    }
}
