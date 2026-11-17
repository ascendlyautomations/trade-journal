import Foundation
import OSLog

enum TradeRoomObsBroadcastDiagnostics {
    private static let logger = Logger(subsystem: AppLog.subsystem, category: "obs-broadcast")

    static func log(
        _ step: String,
        roomID: RoomID,
        sessionId: String? = nil,
        statusCode: Int? = nil,
        detail: String? = nil
    ) {
        var parts = ["[OBS]", "step=\(step)", "room=\(roomID.rawValue)"]
        if let sessionId, !sessionId.isEmpty { parts.append("session=\(sessionId)") }
        if let statusCode { parts.append("http=\(statusCode)") }
        if let detail, !detail.isEmpty { parts.append(detail) }
        let line = parts.joined(separator: " ")
        #if DEBUG
        print(line)
        #endif
        logger.info("\(line, privacy: .public)")
    }

    /// Redact RTMP keys and JWT-like secrets from debug body snippets.
    nonisolated static func redactedBodySnippet(_ data: Data, limit: Int = 240) -> String {
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
