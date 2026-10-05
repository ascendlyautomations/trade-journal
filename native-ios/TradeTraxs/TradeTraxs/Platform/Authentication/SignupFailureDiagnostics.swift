import Foundation

/// Safe signup failure facts. Never includes passwords, tokens, or email addresses.
nonisolated struct SignupFailureReport: Equatable, Sendable {
    enum Source: String, Sendable {
        case supabase
        case localTransport
    }

    var httpStatus: Int?
    var authErrorCode: String?
    var message: String?
    var bodyReceived: Bool
    var source: Source

    var logReason: String {
        let status = httpStatus.map(String.init) ?? "none"
        let code = authErrorCode ?? "none"
        let safeMessage = message ?? "none"
        return "httpStatus=\(status) authErrorCode=\(code) message=\(safeMessage) bodyReceived=\(bodyReceived) source=\(source.rawValue)"
    }
}

/// Lock-protected signup failure facts — safe to record from networking/auth backend tasks.
nonisolated enum SignupFailureDiagnostics {
    private static let lock = NSLock()
    private static var latest: SignupFailureReport?

    static func report(for error: AppError) -> SignupFailureReport {
        guard case .transport(let network) = error else {
            return SignupFailureReport(
                httpStatus: nil,
                authErrorCode: nil,
                message: nil,
                bodyReceived: false,
                source: .localTransport
            )
        }
        switch network {
        case .connectivity, .timeout, .cancelled:
            return SignupFailureReport(
                httpStatus: nil,
                authErrorCode: nil,
                message: nil,
                bodyReceived: false,
                source: .localTransport
            )
        case .unknown:
            return SignupFailureReport(
                httpStatus: nil,
                authErrorCode: nil,
                message: nil,
                bodyReceived: false,
                source: .localTransport
            )
        case .unauthorized:
            return SignupFailureReport(
                httpStatus: 401,
                authErrorCode: nil,
                message: nil,
                bodyReceived: false,
                source: .supabase
            )
        case .forbidden:
            return SignupFailureReport(
                httpStatus: 403,
                authErrorCode: nil,
                message: nil,
                bodyReceived: false,
                source: .supabase
            )
        case .rateLimited:
            return SignupFailureReport(
                httpStatus: 429,
                authErrorCode: nil,
                message: nil,
                bodyReceived: false,
                source: .supabase
            )
        case .server(let statusCode, let message):
            let parsed = parsedBody(message)
            return SignupFailureReport(
                httpStatus: statusCode,
                authErrorCode: parsed.code,
                message: parsed.message,
                bodyReceived: parsed.bodyReceived,
                source: .supabase
            )
        case .validation(let statusCode, let message):
            let parsed = parsedBody(message)
            return SignupFailureReport(
                httpStatus: statusCode,
                authErrorCode: parsed.code,
                message: parsed.message,
                bodyReceived: parsed.bodyReceived,
                source: .supabase
            )
        case .decoding:
            return SignupFailureReport(
                httpStatus: nil,
                authErrorCode: nil,
                message: nil,
                bodyReceived: true,
                source: .supabase
            )
        }
    }

    static func record(_ error: AppError) {
        let report = report(for: error)
        lock.lock()
        latest = report
        lock.unlock()
        #if DEBUG
        AuthLifecycleTrace.log(
            operation: "signUp.failed",
            phase: "signupResponse",
            decision: "rejected",
            reason: report.logReason
        )
        #endif
    }

    static func consumeLogReason() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let reason = latest?.logReason
        latest = nil
        return reason
    }

    static func reset() {
        lock.lock()
        latest = nil
        lock.unlock()
    }

    private static func parsedBody(_ raw: String?) -> (code: String?, message: String?, bodyReceived: Bool) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed != "Request failed" else {
            return (nil, nil, false)
        }
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONDecoder().decode(Wire.self, from: data) {
            return (
                safeCode(object.error_code ?? object.error),
                safeMessage(object.msg ?? object.message ?? object.error_description),
                true
            )
        }
        return (nil, safeMessage(trimmed), true)
    }

    private static func safeCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return trimmed
    }

    private static func safeMessage(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.count > 180 {
            text = String(text.prefix(180))
        }
        let lowered = text.lowercased()
        if lowered.contains("password")
            || lowered.contains("bearer ")
            || lowered.contains("access_token")
            || lowered.contains("refresh_token")
            || lowered.contains("eyj")
        {
            return nil
        }
        guard let expression = try? NSRegularExpression(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "[redacted]")
    }

    private struct Wire: Decodable {
        var error: String?
        var error_code: String?
        var error_description: String?
        var msg: String?
        var message: String?
    }
}
