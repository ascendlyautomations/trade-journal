import Foundation

/// Maps `/api/analyze-trade` HTTP bodies using the shared web contract.
///
/// Never logs or returns raw JSON/HTML payloads as user-facing copy.
nonisolated enum TradeAIAnalyzeHTTPMapping {
    static func map(statusCode: Int, data: Data) -> TradeAIAnalyzeResponse {
        let decoded = try? JSONDecoder().decode(AnalyzeTradeBFFResponse.self, from: data)
        let reply = trimmed(decoded?.reply)
        let result = trimmed(decoded?.result)
        let error = trimmed(decoded?.error)
        let category = failureCategory(statusCode: statusCode, data: data, decoded: decoded)

        switch statusCode {
        case 200 ... 299:
            if let text = firstUserFacing([reply, result]) {
                TradeAITrace.analysisDecoded()
                return TradeAIAnalyzeResponse(
                    reply: AIGeneratedTextNormalizer.normalize(text),
                    shouldPersist: true
                )
            }
            TradeAITrace.analysisFailed(
                status: statusCode,
                byteCount: data.count,
                category: category
            )
            return TradeAIAnalyzeResponse(
                reply: userFacingMessage(
                    statusCode: statusCode,
                    reply: reply,
                    error: error,
                    fallback: "No response generated"
                ),
                shouldPersist: false
            )
        default:
            TradeAITrace.analysisFailed(
                status: statusCode,
                byteCount: data.count,
                category: category
            )
            return TradeAIAnalyzeResponse(
                reply: userFacingMessage(
                    statusCode: statusCode,
                    reply: reply,
                    error: error,
                    fallback: "We couldn't complete the analysis. Please try again."
                ),
                shouldPersist: false
            )
        }
    }

    static func failureCategory(
        statusCode: Int,
        data: Data,
        decoded: AnalyzeTradeBFFResponse?
    ) -> String {
        if looksLikeHTML(data) { return "html" }
        if (200 ... 299).contains(statusCode),
           trimmed(decoded?.reply) == nil,
           trimmed(decoded?.result) == nil
        {
            return decoded == nil && !data.isEmpty ? "decoding" : "empty"
        }
        switch statusCode {
        case 401: return "unauthorized"
        case 403: return "forbidden"
        case 429: return "rateLimited"
        case 400 ..< 500: return "client"
        case 500 ..< 600: return "server"
        default: return "unknown"
        }
    }

    private static func userFacingMessage(
        statusCode: Int,
        reply: String?,
        error: String?,
        fallback: String
    ) -> String {
        if statusCode == 403 {
            return AIGeneratedTextNormalizer.normalize(
                ProEntitlementResponseSanitizer.message(
                    statusCode: 403,
                    error: error,
                    reply: reply
                )
            )
        }

        if let text = firstUserFacing([reply, error]) {
            return AIGeneratedTextNormalizer.normalize(
                ProEntitlementResponseSanitizer.sanitizedOrNeutral(text)
            )
        }
        return fallback
    }

    private static func firstUserFacing(_ candidates: [String?]) -> String? {
        for candidate in candidates {
            guard let candidate, isUserFacingText(candidate) else { continue }
            return candidate
        }
        return nil
    }

    private static func isUserFacingText(_ text: String) -> Bool {
        if text.hasPrefix("{") || text.hasPrefix("[") { return false }
        let lowered = text.lowercased()
        if lowered.hasPrefix("<!doctype") || lowered.hasPrefix("<html") { return false }
        return true
    }

    private static func looksLikeHTML(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(64), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return false }
        return prefix.hasPrefix("<!doctype") || prefix.hasPrefix("<html")
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated struct AnalyzeTradeBFFResponse: Decodable, Sendable {
    var reply: String?
    var result: String?
    var error: String?
}
