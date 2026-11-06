import Foundation

nonisolated struct LiveKitBroadcastStatusResponse: Decodable, Sendable {
    var live: Bool
    var broadcastSessionId: String?
    var broadcasterUserId: String?
    var broadcasterDisplayName: String?
    var startedAt: String?
    var voiceMode: String?
    var videoSource: String?
    var viewerCount: Int?

    enum CodingKeys: String, CodingKey {
        case live
        case broadcastSessionId
        case broadcasterUserId
        case broadcasterDisplayName
        case startedAt
        case voiceMode
        case videoSource
        case viewerCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        live = try container.decodeIfPresent(Bool.self, forKey: .live) ?? false
        broadcastSessionId = try container.decodeIfPresent(String.self, forKey: .broadcastSessionId)
        broadcasterUserId = try container.decodeIfPresent(String.self, forKey: .broadcasterUserId)
        broadcasterDisplayName = try container.decodeIfPresent(
            String.self,
            forKey: .broadcasterDisplayName
        )
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        voiceMode = try container.decodeIfPresent(String.self, forKey: .voiceMode)
        videoSource = try container.decodeIfPresent(String.self, forKey: .videoSource)
        viewerCount = try container.decodeIfPresent(Int.self, forKey: .viewerCount)
    }
}

nonisolated struct LiveKitBroadcastTokenResponse: Decodable, Sendable {
    var token: String
    var livekitUrl: String
    var roomName: String
    var role: String
    var canPublish: Bool
    var canSubscribe: Bool
    var canPublishData: Bool
    var expiresInSeconds: Int
    var broadcastSessionId: String?
    var broadcasterUserId: String?
    var broadcasterDisplayName: String?
    var startedAt: String?
    var voiceMode: String?
    var videoSource: String?
}

nonisolated struct LiveKitBroadcastClient: Sendable {
    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func fetchStatus(roomID: RoomID) async throws -> LiveKitBroadcastStatusResponse {
        let path =
            "/api/livekit/broadcast/status?roomId=\(roomID.rawValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? roomID.rawValue)"
        let response = try await transport.send(
            host: .bff,
            path: path,
            method: .get,
            headers: [:],
            body: nil,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: decodeError(response))
        }
        return try transport.decoder.decode(LiveKitBroadcastStatusResponse.self, from: response)
    }

    func fetchViewerToken(roomID: RoomID) async throws -> LiveKitBroadcastTokenResponse {
        try await postToken(path: "/api/livekit/broadcast/token", roomID: roomID)
    }

    func joinConversation(roomID: RoomID) async throws -> LiveKitBroadcastTokenResponse {
        try await postToken(path: "/api/livekit/broadcast/join-conversation", roomID: roomID)
    }

    func leaveConversation(roomID: RoomID) async throws -> LiveKitBroadcastTokenResponse? {
        struct Body: Encodable { var roomId: String }
        struct Envelope: Decodable {
            var viewerToken: LiveKitBroadcastTokenResponse?
        }
        let body = try JSONEncoder().encode(Body(roomId: roomID.rawValue))
        let response = try await transport.send(
            host: .bff,
            path: "/api/livekit/broadcast/leave-conversation",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: body,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: decodeError(response))
        }
        let envelope = try transport.decoder.decode(Envelope.self, from: response)
        return envelope.viewerToken
    }

    private func postToken(path: String, roomID: RoomID) async throws -> LiveKitBroadcastTokenResponse {
        struct Body: Encodable { var roomId: String }
        let body = try JSONEncoder().encode(Body(roomId: roomID.rawValue))
        let response = try await transport.send(
            host: .bff,
            path: path,
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: body,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: decodeError(response))
        }
        return try transport.decoder.decode(LiveKitBroadcastTokenResponse.self, from: response)
    }

    private func decodeError(_ response: HTTPResponse) -> String {
        String(data: response.data, encoding: .utf8) ?? "Broadcast request failed."
    }
}
