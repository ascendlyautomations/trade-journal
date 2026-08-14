import Foundation
import OSLog

/// Mirrors web `createDirectMessagePush` → `POST /api/messaging/notify-dm`.
///
/// Messaging push only — never creates an Activity/`notifications` row.
/// Failures are logged and never thrown to the message send path.
nonisolated struct DirectMessagePushClient: Sendable {
    private let transport: SupabaseTransport?

    init(transport: SupabaseTransport?) {
        self.transport = transport
    }

    /// Invokes the existing server DM push pipeline for a persisted message.
    func notifyAfterSuccessfulInsert(messageID: String) async {
        let trimmed = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let transport else {
            AppLog.notifications.error("DM push skipped: network transport unavailable")
            return
        }

        do {
            struct Body: Encodable {
                var messageId: String
            }

            let data = try transport.encodeJSON(Body(messageId: trimmed))
            let response = try await transport.send(
                host: .bff,
                path: "/api/messaging/notify-dm",
                method: .post,
                body: data,
                requiresAuthentication: true
            )
            guard (200 ... 299).contains(response.statusCode) else {
                let snippet = String(data: response.data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(200) ?? ""
                AppLog.notifications.error(
                    """
                    DM push notify failed \
                    status=\(response.statusCode, privacy: .public) \
                    messageId=\(trimmed, privacy: .public) \
                    body=\(String(snippet), privacy: .public)
                    """
                )
                return
            }
            AppLog.notifications.info(
                "DM push notify ok messageId=\(trimmed, privacy: .public)"
            )
        } catch {
            AppLog.notifications.error(
                "DM push notify error: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
