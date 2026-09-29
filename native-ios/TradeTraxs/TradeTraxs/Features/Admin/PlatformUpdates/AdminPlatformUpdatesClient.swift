import Foundation

struct AdminPlatformUpdateRow: Identifiable, Decodable, Sendable, Hashable {
    var id: String
    var title: String
    var body: String
    var category: String
    var destination: String
    var sendPush: Bool
    var status: String
    var publishAt: String?
    var publishedAt: String?
    var broadcast: AdminPlatformUpdateBroadcast?

    struct AdminPlatformUpdateBroadcast: Decodable, Sendable, Hashable {
        var status: String
        var attemptedCount: Int
        var successCount: Int
        var failedCount: Int
    }
}

enum AdminPlatformUpdatesClient {
    private struct ListPayload: Decodable {
        var updates: [AdminPlatformUpdateRow]?
    }

    private struct SinglePayload: Decodable {
        var update: AdminPlatformUpdateRow?
        var error: String?
    }

    static func fetchAll(transport: SupabaseTransport) async throws -> [AdminPlatformUpdateRow] {
        let response = try await transport.send(
            host: .bff,
            path: "/api/admin/platform-updates",
            method: .get,
            requiresAuthentication: true
        )
        let decoded = try PlatformUpdatesBFFClient.decodeSuccess(ListPayload.self, transport: transport, response: response)
        return decoded.updates ?? []
    }

    static func create(
        transport: SupabaseTransport,
        body: [String: Any]
    ) async throws -> AdminPlatformUpdateRow {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = try await transport.send(
            host: .bff,
            path: "/api/admin/platform-updates",
            method: .post,
            body: data,
            requiresAuthentication: true
        )
        let decoded = try PlatformUpdatesBFFClient.decodeSuccess(SinglePayload.self, transport: transport, response: response)
        guard let update = decoded.update else {
            throw AppError.unknown(message: decoded.error ?? "Save failed.")
        }
        return update
    }

    static func patch(
        transport: SupabaseTransport,
        id: String,
        body: [String: Any]
    ) async throws {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = try await transport.send(
            host: .bff,
            path: "/api/admin/platform-updates/\(id)",
            method: .patch,
            body: data,
            requiresAuthentication: true
        )
        _ = try PlatformUpdatesBFFClient.decodeSuccess(SinglePayload.self, transport: transport, response: response)
    }

    static func publish(transport: SupabaseTransport, id: String) async throws {
        let response = try await transport.send(
            host: .bff,
            path: "/api/admin/platform-updates/\(id)/publish",
            method: .post,
            requiresAuthentication: true
        )
        struct PublishPayload: Decodable {
            var ok: Bool?
            var error: String?
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw PlatformUpdatesBFFClient.bffFailure(from: response)
        }
        let decoded = try transport.decoder.decode(PublishPayload.self, from: response)
        if decoded.ok != true {
            throw AppError.unknown(message: decoded.error ?? "Publish failed.")
        }
    }
}
