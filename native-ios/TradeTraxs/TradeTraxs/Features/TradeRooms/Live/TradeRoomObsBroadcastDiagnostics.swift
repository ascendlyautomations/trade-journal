import Foundation

enum TradeRoomObsBroadcastDiagnostics {
    static func log(
        _ step: String,
        roomID: RoomID,
        sessionId: String? = nil,
        statusCode: Int? = nil,
        detail: String? = nil
    ) {
        #if DEBUG
        var parts = ["[OBS]", "step=\(step)", "room=\(roomID.rawValue)"]
        if let sessionId, !sessionId.isEmpty { parts.append("session=\(sessionId)") }
        if let statusCode { parts.append("http=\(statusCode)") }
        if let detail, !detail.isEmpty { parts.append(detail) }
        print(parts.joined(separator: " "))
        #endif
    }

    /// Redact RTMP keys and JWT-like secrets from debug body snippets.
    static func redactedBodySnippet(_ data: Data, limit: Int = 240) -> String {
        guard let raw = String(data: data, encoding: .utf8) else { return "<non-utf8>" }
        let redacted = raw
            .replacingOccurrences(
                of: #""streamKey"\s*:\s*"[^"]*""#,
                with: #""streamKey":"[redacted]""#,
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #""token"\s*:\s*"[^"]{8,}[^"]*""#,
                with: #""token":"[redacted]""#,
                options: .regularExpression
            )
        if redacted.count <= limit { return redacted }
        return String(redacted.prefix(limit)) + "…"
    }
}
