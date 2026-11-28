import Foundation

/// Maps `/api/ai/trade-turn` and `/api/ai/portfolio-turn` bodies (shared contract).
nonisolated enum TradeAITurnHTTPMapping {
    private static let genericFailure = "We couldn't complete the analysis. Please try again."

    static func map(statusCode: Int, data: Data) -> TradeAITurnResponse {
        let decoded = try? JSONDecoder().decode(TradeTurnBFFResponse.self, from: data)
        let fallback = extractFallbackFields(from: data)

        let backendCode = trimmed(decoded?.code) ?? trimmed(fallback.code)
        let category = failureCategory(
            statusCode: statusCode,
            data: data,
            decoded: decoded,
            backendCode: backendCode,
            fallbackHasReply: trimmed(fallback.reply) != nil || trimmed(fallback.result) != nil
        )

        if statusCode == 403, backendCode == "pro_required" {
            TradeAITrace.tradeTurnMapped(
                status: statusCode,
                byteCount: data.count,
                decoded: decoded != nil,
                replyLength: 0,
                shouldPersist: false,
                backendCode: backendCode,
                analysisSucceeded: true
            )
            return TradeAITurnResponse(
                reply: TraxProFeatureMessaging.featureRequired,
                conversationID: AIConversationID(decoded?.conversationId ?? fallback.conversationId ?? UUID().uuidString),
                userMessageID: decoded?.userMessageId ?? fallback.userMessageId ?? UUID().uuidString,
                assistantMessageID: decoded?.assistantMessageId ?? fallback.assistantMessageId ?? UUID().uuidString,
                shouldPersist: false,
                persistError: nil,
                backendCode: "pro_required",
                analysisSucceeded: true
            )
        }

        #if DEBUG
        if decoded == nil, !data.isEmpty {
            TradeAITrace.tradeTurnDecodeFailed(
                status: statusCode,
                byteCount: data.count,
                category: category
            )
        }
        #endif

        let rawReply = firstUserFacing([
            trimmed(decoded?.reply),
            trimmed(decoded?.result),
            trimmed(fallback.reply),
            trimmed(fallback.result),
        ])
        let rawError = firstUserFacing([
            trimmed(decoded?.error),
            trimmed(fallback.error),
        ])

        let normalizedReply = rawReply.map { AIGeneratedTextNormalizer.normalize($0) }
        let shouldPersistFromServer = decoded?.shouldPersist
        let persistError = trimmed(decoded?.persistError) ?? trimmed(fallback.persistError)

        let analysisSucceeded: Bool
        let reply: String
        let shouldPersist: Bool

        if let normalizedReply, !normalizedReply.isEmpty {
            analysisSucceeded = true
            reply = normalizedReply
            shouldPersist = (shouldPersistFromServer ?? true) && persistError == nil
        } else if (200 ... 299).contains(statusCode) {
            analysisSucceeded = false
            reply = userFacingFailure(
                statusCode: statusCode,
                error: rawError,
                backendCode: backendCode,
                fallback: genericFailure
            )
            shouldPersist = false
        } else {
            analysisSucceeded = false
            reply = userFacingFailure(
                statusCode: statusCode,
                error: rawError,
                backendCode: backendCode,
                fallback: genericFailure
            )
            shouldPersist = false
        }

        TradeAITrace.tradeTurnMapped(
            status: statusCode,
            byteCount: data.count,
            decoded: decoded != nil,
            replyLength: normalizedReply?.count ?? 0,
            shouldPersist: shouldPersist,
            backendCode: backendCode,
            analysisSucceeded: analysisSucceeded
        )

        return TradeAITurnResponse(
            reply: reply,
            conversationID: AIConversationID(decoded?.conversationId ?? fallback.conversationId ?? UUID().uuidString),
            userMessageID: decoded?.userMessageId ?? fallback.userMessageId ?? UUID().uuidString,
            assistantMessageID: decoded?.assistantMessageId ?? fallback.assistantMessageId ?? UUID().uuidString,
            shouldPersist: shouldPersist,
            persistError: persistError,
            backendCode: backendCode,
            analysisSucceeded: analysisSucceeded
        )
    }

    static func failureCategory(
        statusCode: Int,
        data: Data,
        decoded: TradeTurnBFFResponse?,
        backendCode: String?,
        fallbackHasReply: Bool
    ) -> String {
        if let backendCode, !backendCode.isEmpty { return backendCode }
        if looksLikeHTML(data) { return "html" }
        if (200 ... 299).contains(statusCode), decoded == nil, !data.isEmpty {
            return fallbackHasReply ? "partial_decode" : "decoding"
        }
        if (200 ... 299).contains(statusCode), decoded != nil,
           trimmed(decoded?.reply) == nil, trimmed(decoded?.result) == nil
        {
            return "empty"
        }
        switch statusCode {
        case 401: return "unauthorized"
        case 403: return "forbidden"
        case 429: return "rateLimited"
        case 502, 503: return "serviceUnavailable"
        case 400 ..< 500: return "client"
        case 500 ..< 600: return "server"
        default: return "unknown"
        }
    }

    private struct FallbackFields {
        var reply: String?
        var result: String?
        var error: String?
        var code: String?
        var conversationId: String?
        var userMessageId: String?
        var assistantMessageId: String?
        var persistError: String?
        var shouldPersist: Bool?
    }

    private static func extractFallbackFields(from data: Data) -> FallbackFields {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return FallbackFields()
        }
        return FallbackFields(
            reply: object["reply"] as? String,
            result: object["result"] as? String,
            error: object["error"] as? String,
            code: object["code"] as? String,
            conversationId: object["conversationId"] as? String,
            userMessageId: object["userMessageId"] as? String,
            assistantMessageId: object["assistantMessageId"] as? String,
            persistError: object["persistError"] as? String,
            shouldPersist: object["shouldPersist"] as? Bool
        )
    }

    private static func userFacingFailure(
        statusCode: Int,
        error: String?,
        backendCode: String?,
        fallback: String
    ) -> String {
        if let error, isUserFacingText(error) {
            return AIGeneratedTextNormalizer.normalize(
                ProEntitlementResponseSanitizer.sanitizedOrNeutral(error)
            )
        }
        if let code = backendCode, let coded = messageForKnownBackendCode(code) {
            return AIGeneratedTextNormalizer.normalize(coded)
        }
        if statusCode == 429 {
            return "Trade AI is busy right now. Wait a moment and try again."
        }
        return fallback
    }

    private static func messageForKnownBackendCode(_ code: String) -> String? {
        switch code {
        case "persist_failed":
            return "Analysis completed but could not be saved. Try again."
        case "trade_not_found":
            return "We couldn't find that trade. Refresh and try again."
        case "openai_quota_exhausted":
            return "Trade AI is temporarily unavailable. Please try again later."
        case "openai_rate_limited":
            return "Trade AI is busy right now. Wait a moment and try again."
        default:
            return nil
        }
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

nonisolated struct TradeTurnBFFResponse: Decodable, Sendable {
    var reply: String?
    var result: String?
    var error: String?
    var conversationId: String?
    var userMessageId: String?
    var assistantMessageId: String?
    var shouldPersist: Bool?
    var persistError: String?
    var code: String?
}