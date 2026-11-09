import Foundation

nonisolated struct LiveKitVoicePresenceResponse: Decodable, Sendable {
    var connectedCount: Int
    var speakingCount: Int
}

nonisolated struct LiveKitVoiceTokenResponse: Decodable, Sendable {
    var token: String
    var livekitUrl: String
    var roomName: String
    var mode: String
    var role: String
    var canPublish: Bool
    var expiresInSeconds: Int
}

nonisolated struct LiveKitTokenClient: Sendable {
    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func fetchVoiceToken(roomID: RoomID) async throws -> LiveKitVoiceTokenResponse {
        struct Body: Encodable {
            var roomId: String
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        let body = try encoder.encode(Body(roomId: roomID.rawValue))

        let response = try await transport.send(
            host: .bff,
            path: "/api/livekit/token",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: body,
            requiresAuthentication: true
        )

        guard (200 ... 299).contains(response.statusCode) else {
            let message = String(data: response.data, encoding: .utf8) ?? "Could not join live voice."
            throw AppError.unknown(message: message)
        }

        return try transport.decoder.decode(LiveKitVoiceTokenResponse.self, from: response)
    }

    func fetchVoicePresence(roomID: RoomID) async throws -> LiveKitVoicePresenceResponse {
        let encoded =
            roomID.rawValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? roomID.rawValue
        let response = try await transport.send(
            host: .bff,
            path: "/api/livekit/voice/presence?roomId=\(encoded)",
            method: .get,
            headers: [:],
            body: nil,
            requiresAuthentication: true
        )

        guard (200 ... 299).contains(response.statusCode) else {
            let message =
                String(data: response.data, encoding: .utf8) ?? "Could not read voice presence."
            throw AppError.unknown(message: message)
        }

        return try transport.decoder.decode(LiveKitVoicePresenceResponse.self, from: response)
    }
}
