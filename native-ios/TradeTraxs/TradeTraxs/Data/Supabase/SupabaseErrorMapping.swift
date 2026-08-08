import Foundation

/// Maps Supabase / PostgREST / GoTrue / Storage failures into ``AppError`` (never exposes SDK types).
nonisolated enum SupabaseErrorMapping {
    static func mapNetwork(_ error: Error) -> AppError {
        if let network = error as? NetworkError {
            return mapNetworkError(network)
        }
        if let app = error as? AppError {
            return app
        }
        if let auth = error as? AuthenticationError {
            return .from(auth)
        }
        return .unknown(message: "Supabase request failed")
    }

    static func mapNetworkError(_ error: NetworkError) -> AppError {
        switch error {
        case .cancelled:
            return .cancelled
        case .unauthorized, .forbidden:
            return .authentication(.sessionExpired)
        case .server(let code, let message):
            if code == 401 || code == 403 {
                return .authentication(.invalidCredentials)
            }
            if code == 404 {
                return .unknown(message: message ?? "Not found")
            }
            return .transport(error)
        default:
            return .transport(error)
        }
    }

    static func mapAuthHTTP(statusCode: Int, body: Data) -> AuthenticationError {
        let message = String(data: body, encoding: .utf8) ?? ""
        let lowered = message.lowercased()
        if statusCode == 400 || statusCode == 401 {
            if lowered.contains("invalid login") || lowered.contains("invalid_grant") {
                return .invalidCredentials
            }
            if lowered.contains("email") {
                return .invalidEmail
            }
            return .invalidCredentials
        }
        if statusCode == 422 {
            return .validation(message)
        }
        return .unknown("Auth failed (\(statusCode))")
    }
}
