import Foundation
import OSLog

/// Fetches the canonical app-icon badge from the BFF BadgeService.
protocol AppIconBadgeClienting: Sendable {
    func fetchBadge() async throws -> Int
}

/// GET `/api/push/badge` — server is the only calculator.
struct AppIconBadgeClient: AppIconBadgeClienting {
    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func fetchBadge() async throws -> Int {
        struct ResponseBody: Decodable {
            var badge: Int
        }

        let body = try await transport.sendDecodable(
            ResponseBody.self,
            host: .bff,
            path: "/api/push/badge",
            method: .get,
            body: nil,
            requiresAuthentication: true
        )
        return max(0, body.badge)
    }
}
