import Foundation

struct PlatformUpdateItem: Identifiable, Decodable, Sendable, Hashable {
    var id: String
    var title: String
    var body: String
    var category: String
    var destination: String
    var href: String
    var publishedAt: String?
}

enum PlatformWhatsNewClient {
    private struct Payload: Decodable {
        var updates: [PlatformUpdateItem]?
    }

    static func fetchPublished(transport: SupabaseTransport) async throws -> [PlatformUpdateItem] {
        let response = try await transport.send(
            host: .bff,
            path: "/api/platform-updates",
            method: .get,
            requiresAuthentication: true
        )
        let decoded = try PlatformUpdatesBFFClient.decodeSuccess(Payload.self, transport: transport, response: response)
        return decoded.updates ?? []
    }
}
