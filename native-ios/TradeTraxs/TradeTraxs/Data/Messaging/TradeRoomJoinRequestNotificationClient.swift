import Foundation
import OSLog

/// Mirrors web join-request notify → `POST /api/notifications/trade-room-join-request`.
///
/// Activity row + APNs are created server-side via the existing notification pipeline.
/// Failures are logged and never thrown to the join-request path.
nonisolated struct TradeRoomJoinRequestNotificationClient: Sendable {
    private let transport: SupabaseTransport?

    init(transport: SupabaseTransport?) {
        self.transport = transport
    }

    /// Invokes the existing server notification pipeline after a pending join request is created.
    func notifyAfterJoinRequest(roomID: RoomID, requestID: String) async {
        let trimmedRequestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRequestID.isEmpty else { return }
        guard let transport else {
            AppLog.notifications.error("Trade room join request notify skipped: network transport unavailable")
            return
        }

        do {
            struct Body: Encodable {
                var roomId: String
                var requestId: String
            }

            let data = try transport.encodeJSON(
                Body(roomId: roomID.rawValue, requestId: trimmedRequestID)
            )
            let response = try await transport.send(
                host: .bff,
                path: "/api/notifications/trade-room-join-request",
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
                    Trade room join request notify failed \
                    status=\(response.statusCode, privacy: .public) \
                    requestId=\(trimmedRequestID, privacy: .public) \
                    body=\(String(snippet), privacy: .public)
                    """
                )
                return
            }
            AppLog.notifications.info(
                "Trade room join request notify ok requestId=\(trimmedRequestID, privacy: .public)"
            )
        } catch {
            AppLog.notifications.error(
                "Trade room join request notify error: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
