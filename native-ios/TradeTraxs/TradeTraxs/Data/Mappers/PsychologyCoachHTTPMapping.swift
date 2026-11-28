import Foundation

/// Maps `/api/psychology-coach` responses (same transport contract as Trade AI turns).
nonisolated enum PsychologyCoachHTTPMapping {
    private static let genericFailure =
        "Psychology coach unavailable. Your analytics still work offline."

    static func map(statusCode: Int, data: Data) throws -> PsychologyCoachAIResponse {
        let decoded = try? JSONDecoder().decode(PsychologyCoachBFFResponse.self, from: data)
        let fallback = extractFallbackFields(from: data)

        let category = failureCategory(
            statusCode: statusCode,
            data: data,
            decoded: decoded,
            fallbackHasReply: trimmed(fallback.reply) != nil
        )

        #if DEBUG
        PsychologyCoachTrace.decodeResult(
            decoded: decoded != nil,
            category: category,
            replyLength: trimmed(decoded?.reply)?.count ?? trimmed(fallback.reply)?.count ?? 0
        )
        #endif

        let rawReply = firstNonEmpty([
            trimmed(decoded?.reply),
            trimmed(fallback.reply),
        ])

        if statusCode == 403 {
            let message = ProEntitlementResponseSanitizer.message(
                statusCode: 403,
                error: trimmed(decoded?.error) ?? trimmed(fallback.error),
                reply: rawReply
            )
            throw AppError.unknown(message: message)
        }

        if (200 ... 299).contains(statusCode),
            let rawReply,
            !rawReply.isEmpty
        {
            let normalized = AIGeneratedTextNormalizer.normalize(rawReply)
            guard !normalized.isEmpty else {
                throw AppError.unknown(message: "No response generated")
            }
            let conversationID = (trimmed(decoded?.conversationId) ?? trimmed(fallback.conversationId))
                .flatMap { AIConversationID($0) }
            return PsychologyCoachAIResponse(
                reply: normalized,
                conversationID: conversationID,
                assistantMessageID: trimmed(decoded?.assistantMessageId) ?? trimmed(fallback.assistantMessageId)
            )
        }

        #if DEBUG
        PsychologyCoachTrace.requestFailed(status: statusCode, byteCount: data.count, category: category)
        #endif

        if let rawReply, !rawReply.isEmpty {
            throw AppError.unknown(message: AIGeneratedTextNormalizer.normalize(rawReply))
        }

        if statusCode == 401 {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        if statusCode == 429 {
            throw AppError.unknown(
                message: trimmed(decoded?.error) ?? trimmed(fallback.error)
                    ?? "Slow down, try again in a moment."
            )
        }

        let serverError = trimmed(decoded?.error) ?? trimmed(fallback.error)
        throw AppError.unknown(
            message: ProEntitlementResponseSanitizer.sanitizedOrNeutral(
                serverError ?? genericFailure
            )
        )
    }

    private struct FallbackFields {
        var reply: String?
        var error: String?
        var conversationId: String?
        var assistantMessageId: String?
    }

    private static func extractFallbackFields(from data: Data) -> FallbackFields {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return FallbackFields()
        }
        return FallbackFields(
            reply: object["reply"] as? String,
            error: object["error"] as? String,
            conversationId: object["conversationId"] as? String,
            assistantMessageId: object["assistantMessageId"] as? String
        )
    }

    private static func failureCategory(
        statusCode: Int,
        data: Data,
        decoded: PsychologyCoachBFFResponse?,
        fallbackHasReply: Bool
    ) -> String {
        if looksLikeHTML(data) { return "html" }
        if (200 ... 299).contains(statusCode), decoded == nil, !data.isEmpty {
            return fallbackHasReply ? "partial_decode" : "decoding"
        }
        if (200 ... 299).contains(statusCode), decoded != nil, trimmed(decoded?.reply) == nil {
            return fallbackHasReply ? "partial_decode" : "empty_reply"
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

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstNonEmpty(_ candidates: [String?]) -> String? {
        for candidate in candidates {
            if let candidate = trimmed(candidate) { return candidate }
        }
        return nil
    }

    private static func looksLikeHTML(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(64), encoding: .utf8)?.lowercased() else {
            return false
        }
        return prefix.contains("<!doctype") || prefix.contains("<html")
    }
}

/// BFF wire types shared by ``DefaultAIRepository`` and ``PsychologyCoachHTTPMapping``.
nonisolated struct PsychologyCoachBFFResponse: Decodable {
    var reply: String?
    var error: String?
    var conversationId: String?
    var assistantMessageId: String?
}