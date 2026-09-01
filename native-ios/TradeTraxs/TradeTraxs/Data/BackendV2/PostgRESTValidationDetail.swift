import Foundation

/// Privacy-safe PostgREST / HTTP 4xx detail for RPC diagnostics.
nonisolated struct PostgRESTValidationDetail: Sendable, Equatable {
    var httpStatus: Int?
    var code: String?
    var message: String?
    var details: String?
    var hint: String?

    /// Telemetry-safe single-line summary — no raw JSON bodies or secrets.
    var telemetrySummary: String {
        var parts: [String] = ["validation"]
        if let httpStatus { parts.append("status=\(httpStatus)") }
        if let code, !code.isEmpty { parts.append("code=\(Self.safeField(code, max: 48))") }
        if let message, !message.isEmpty { parts.append("message=\(Self.safeField(message, max: 96))") }
        if let details, !details.isEmpty { parts.append("details=\(Self.safeField(details, max: 64))") }
        if let hint, !hint.isEmpty { parts.append("hint=\(Self.safeField(hint, max: 64))") }
        return parts.joined(separator: " ")
    }

    static func parse(httpStatus: Int?, body: String) -> PostgRESTValidationDetail {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return PostgRESTValidationDetail(
                httpStatus: httpStatus,
                code: nil,
                message: safeBodyFallback(trimmed),
                details: nil,
                hint: nil
            )
        }
        return PostgRESTValidationDetail(
            httpStatus: httpStatus,
            code: stringField(object["code"]),
            message: stringField(object["message"]),
            details: stringField(object["details"]),
            hint: stringField(object["hint"])
        )
    }

    private static func stringField(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func safeBodyFallback(_ body: String) -> String? {
        guard !body.isEmpty else { return nil }
        if body.hasPrefix("{") || body.hasPrefix("[") {
            return "jsonBody len=\(body.count)"
        }
        return safeField(body, max: 96)
    }

    static func safeField(_ value: String, max: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "empty" }
        let lowered = trimmed.lowercased()
        if lowered.contains("jwt") || lowered.contains("bearer") || lowered.contains("token") {
            return "redacted"
        }
        if trimmed.count > max {
            return String(trimmed.prefix(max)) + "…"
        }
        return trimmed
    }
}
