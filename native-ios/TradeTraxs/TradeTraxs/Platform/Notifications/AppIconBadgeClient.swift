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
        let response = try await transport.send(
            host: .bff,
            path: "/api/push/badge",
            method: .get,
            body: nil,
            requiresAuthentication: true
        )

        guard (200 ... 299).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw AppError.authentication(.sessionExpired)
            }
            let snippet = String(data: response.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(180) ?? ""
            throw AppError.unknown(
                message: "Badge HTTP \(response.statusCode)\(snippet.isEmpty ? "" : ": \(snippet)")"
            )
        }

        let badge = try Self.decodeBadge(from: response.data)
        return max(0, badge)
    }

    /// Accepts `{ "badge": <int|double|numeric-string> }` from the BFF.
    private static func decodeBadge(from data: Data) throws -> Int {
        if data.isEmpty {
            throw AppError.unknown(message: "Badge response body was empty")
        }

        struct ResponseBody: Decodable {
            var badge: FlexibleInt
        }

        do {
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            return decoded.badge.value
        } catch {
            let snippet = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(180) ?? "<non-utf8>"
            throw AppError.unknown(
                message: "Badge decode failed (\(error.localizedDescription)): \(snippet)"
            )
        }
    }
}

/// JSON number / numeric-string → Int (BFF may serialize counts as number flavors).
private struct FlexibleInt: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            value = Int(doubleValue.rounded(.towardZero))
            return
        }
        if let stringValue = try? container.decode(String.self),
           let parsed = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            value = parsed
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected Int-compatible badge value"
        )
    }
}
