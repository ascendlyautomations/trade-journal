import Foundation

nonisolated struct LiveKitBroadcastStatusResponse: Decodable, Sendable {
    /// Session row may exist while OBS is only preparing; check `publicLive` for discoverable live.
    var live: Bool
    /// When true, viewers may watch / receive go-live semantics. False during OBS private prep.
    var publicLive: Bool?
    var visibility: String?
    var broadcastSessionId: String?
    var broadcasterUserId: String?
    var broadcasterDisplayName: String?
    var startedAt: String?
    var voiceMode: String?
    var videoSource: String?
    /// "browser" or "obs" — Phase 2 uses primaryMediaPublisherIdentity when obs.
    var broadcastSource: String?
    var primaryMediaPublisherIdentity: String?
    var livekitIngressId: String?
    var ingressStatusSnapshot: String?
    var hostConnected: Bool?
    var primaryMediaPublisherConnected: Bool?
    var viewerCount: Int?

    enum CodingKeys: String, CodingKey {
        case live
        case publicLive
        case visibility
        case broadcastSessionId
        case broadcasterUserId
        case broadcasterDisplayName
        case startedAt
        case voiceMode
        case videoSource
        case broadcastSource
        case primaryMediaPublisherIdentity
        case livekitIngressId
        case ingressStatusSnapshot
        case hostConnected
        case primaryMediaPublisherConnected
        case viewerCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        live = try container.decodeIfPresent(Bool.self, forKey: .live) ?? false
        publicLive = try container.decodeIfPresent(Bool.self, forKey: .publicLive)
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility)
        broadcastSessionId = try container.decodeIfPresent(String.self, forKey: .broadcastSessionId)
        broadcasterUserId = try container.decodeIfPresent(String.self, forKey: .broadcasterUserId)
        broadcasterDisplayName = try container.decodeIfPresent(
            String.self,
            forKey: .broadcasterDisplayName
        )
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        voiceMode = try container.decodeIfPresent(String.self, forKey: .voiceMode)
        videoSource = try container.decodeIfPresent(String.self, forKey: .videoSource)
        broadcastSource = try container.decodeIfPresent(String.self, forKey: .broadcastSource)
        primaryMediaPublisherIdentity = try container.decodeIfPresent(
            String.self,
            forKey: .primaryMediaPublisherIdentity
        )
        livekitIngressId = try container.decodeIfPresent(String.self, forKey: .livekitIngressId)
        ingressStatusSnapshot = try container.decodeIfPresent(
            String.self,
            forKey: .ingressStatusSnapshot
        )
        hostConnected = try container.decodeIfPresent(Bool.self, forKey: .hostConnected)
        primaryMediaPublisherConnected = try container.decodeIfPresent(
            Bool.self,
            forKey: .primaryMediaPublisherConnected
        )
        viewerCount = try container.decodeIfPresent(Int.self, forKey: .viewerCount)
    }
}

nonisolated struct LiveKitBroadcastStartResponse: Decodable, Sendable {
    var token: String
    var livekitUrl: String
    var roomName: String?
    var role: String?
    var expiresInSeconds: Int?
    var broadcastSessionId: String?
    var broadcasterUserId: String?
    var broadcasterDisplayName: String?
    var startedAt: String?
    var voiceMode: String?
    var videoSource: String?
    var broadcastSource: String?
    var primaryMediaPublisherIdentity: String?
    var visibility: String?
    var publicLive: Bool?
}

nonisolated struct LiveKitObsCredentialsResponse: Decodable, Sendable {
    var broadcastSessionId: String?
    var broadcastSource: String?
    var primaryMediaPublisherIdentity: String?
    var livekitIngressId: String?
    var ingressStatusSnapshot: String?
    var rtmpUrl: String?
    var streamKey: String?
}

nonisolated struct LiveKitObsStatusResponse: Decodable, Sendable {
    var broadcastSessionId: String?
    var broadcastSource: String?
    var primaryMediaPublisherIdentity: String?
    var livekitIngressId: String?
    var ingressStatusSnapshot: String?
    var hostConnected: Bool?
    var primaryMediaPublisherConnected: Bool?
    var broadcasterConnected: Bool?
    var broadcastSessionActive: Bool?
    var ingressWaitingForObs: Bool?
    var ingressDisconnectedOrEnded: Bool?
}

nonisolated struct LiveKitBroadcastPublishResponse: Decodable, Sendable {
    var ok: Bool?
    var broadcastSessionId: String?
    var alreadyPublic: Bool?
    var error: String?
}

nonisolated struct LiveKitBroadcastStopResponse: Decodable, Sendable {
    var ok: Bool?
}

nonisolated struct LiveKitObsRevokeResponse: Decodable, Sendable {
    var ok: Bool?
    var revoked: Bool?
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
    var broadcastSource: String?
    var primaryMediaPublisherIdentity: String?
}

nonisolated struct LiveKitBroadcastClient: Sendable {
    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func fetchStatus(
        roomID: RoomID,
        reconcile: Bool = false,
        lite: Bool = false
    ) async throws -> LiveKitBroadcastStatusResponse {
        let encoded = roomID.rawValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? roomID.rawValue
        var query = "roomId=\(encoded)"
        if reconcile { query += "&reconcile=1" }
        if lite, !reconcile { query += "&lite=1" }
        let path = "/api/livekit/broadcast/status?\(query)"
        let response = try await transport.send(
            host: .bff,
            path: path,
            method: .get,
            headers: [:],
            body: nil,
            requiresAuthentication: true
        )
        return try decodeSuccessBody(
            LiveKitBroadcastStatusResponse.self,
            response: response,
            path: path,
            method: .get,
            requiresAuthentication: true
        )
    }

    /// Owner/moderator: start a broadcast session (OBS uses host token — mic only, program via ingress).
    func startBroadcast(
        roomID: RoomID,
        voiceMode: String = "broadcast_only",
        videoSource: String = "obs"
    ) async throws -> LiveKitBroadcastStartResponse {
        struct Body: Encodable {
            var roomId: String
            var voiceMode: String
            var videoSource: String
        }
        let body = try JSONEncoder().encode(
            Body(roomId: roomID.rawValue, voiceMode: voiceMode, videoSource: videoSource)
        )
        let response = try await transport.send(
            host: .bff,
            path: "/api/livekit/broadcast/start",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: body,
            requiresAuthentication: true
        )
        return try decodeSuccessBody(
            LiveKitBroadcastStartResponse.self,
            response: response,
            path: "/api/livekit/broadcast/start",
            method: .post,
            requiresAuthentication: true
        )
    }

    func createObsIngressCredentials(roomID: RoomID, sessionId: String) async throws -> LiveKitObsCredentialsResponse {
        struct Body: Encodable {
            var roomId: String
            var sessionId: String
        }
        let body = try JSONEncoder().encode(Body(roomId: roomID.rawValue, sessionId: sessionId))
        let response = try await transport.send(
            host: .bff,
            path: "/api/livekit/broadcast/obs/credentials",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: body,
            requiresAuthentication: true
        )
        let path = "/api/livekit/broadcast/obs/credentials"
        let decoded = try decodeSuccessBody(
            LiveKitObsCredentialsResponse.self,
            response: response,
            path: path,
            method: .post,
            requiresAuthentication: true
        )
        let rtmp = decoded.rtmpUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = decoded.streamKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rtmp.isEmpty || key.isEmpty {
            throw AppError.unknown(
                message: "Server returned invalid OBS credentials (missing RTMP URL or stream key)."
            )
        }
        return decoded
    }

    func fetchObsStatus(roomID: RoomID, sessionId: String) async throws -> LiveKitObsStatusResponse {
        let rid = roomID.rawValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? roomID.rawValue
        let sid = sessionId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sessionId
        let path = "/api/livekit/broadcast/obs/status?roomId=\(rid)&sessionId=\(sid)"
        let response = try await transport.send(
            host: .bff,
            path: path,
            method: .get,
            headers: [:],
            body: nil,
            requiresAuthentication: true
        )
        return try decodeSuccessBody(
            LiveKitObsStatusResponse.self,
            response: response,
            path: path,
            method: .get,
            requiresAuthentication: true
        )
    }

    func publishBroadcast(roomID: RoomID) async throws -> LiveKitBroadcastPublishResponse {
        struct Body: Encodable { var roomId: String }
        let body = try JSONEncoder().encode(Body(roomId: roomID.rawValue))
        let response = try await transport.send(
            host: .bff,
            path: "/api/livekit/broadcast/publish",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: body,
            requiresAuthentication: true
        )
        let decoded = try transport.decoder.decode(LiveKitBroadcastPublishResponse.self, from: response)
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: decoded.error ?? decodeError(response))
        }
        return decoded
    }

    func stopBroadcast(roomID: RoomID, sessionId: String) async throws {
        struct Body: Encodable {
            var roomId: String
            var sessionId: String
        }
        let body = try JSONEncoder().encode(Body(roomId: roomID.rawValue, sessionId: sessionId))
        let response = try await transport.send(
            host: .bff,
            path: "/api/livekit/broadcast/stop",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: body,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: decodeError(response))
        }
    }

    func revokeObsIngress(roomID: RoomID, sessionId: String) async throws {
        struct Body: Encodable {
            var roomId: String
            var sessionId: String
        }
        let body = try JSONEncoder().encode(Body(roomId: roomID.rawValue, sessionId: sessionId))
        let response = try await transport.send(
            host: .bff,
            path: "/api/livekit/broadcast/obs/revoke",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: body,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: decodeError(response))
        }
    }

    func fetchViewerToken(roomID: RoomID) async throws -> LiveKitBroadcastTokenResponse {
        try await postToken(path: "/api/livekit/broadcast/token", roomID: roomID)
    }

    func joinConversation(roomID: RoomID) async throws -> LiveKitBroadcastTokenResponse {
        try await postToken(path: "/api/livekit/broadcast/join-conversation", roomID: roomID)
    }

    func syncRaisedHand(roomID: RoomID, sessionId: String, raised: Bool) async throws {
        struct Body: Encodable {
            var roomId: String
            var sessionId: String
            var raised: Bool
        }
        let body = try JSONEncoder().encode(
            Body(roomId: roomID.rawValue, sessionId: sessionId, raised: raised)
        )
        let response = try await transport.send(
            host: .bff,
            path: "/api/livekit/broadcast/hand",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: body,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: decodeError(response))
        }
    }

    func fetchInteractiveState(roomID: RoomID) async throws -> LiveKitBroadcastInteractiveStateResponse {
        let encoded =
            roomID.rawValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? roomID.rawValue
        let path = "/api/livekit/broadcast/interactive-state?roomId=\(encoded)"
        let response = try await transport.send(
            host: .bff,
            path: path,
            method: .get,
            headers: [:],
            body: nil,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: decodeAPIError(response))
        }
        return try transport.decoder.decode(
            LiveKitBroadcastInteractiveStateResponse.self,
            from: response
        )
    }

    func respondToSpeakInvitation(
        invitationId: String,
        accept: Bool
    ) async throws -> LiveKitBroadcastInviteRespondResponse {
        struct Body: Encodable {
            var invitationId: String
            var accept: Bool
        }
        let body = try JSONEncoder().encode(Body(invitationId: invitationId, accept: accept))
        let response = try await transport.send(
            host: .bff,
            path: "/api/livekit/broadcast/invite/respond",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: body,
            requiresAuthentication: true
        )
        let decoded = try transport.decoder.decode(
            LiveKitBroadcastInviteRespondResponse.self,
            from: response
        )
        guard (200 ... 299).contains(response.statusCode) else {
            #if DEBUG
            print(
                """
                [TradeTraxs Broadcast] invite/respond failed \
                endpoint=POST /api/livekit/broadcast/invite/respond \
                status=\(response.statusCode) \
                accept=\(accept) \
                invitationId=\(invitationId) \
                error=\(decoded.error ?? decodeAPIError(response))
                """
            )
            #endif
            throw AppError.unknown(message: decoded.error ?? decodeAPIError(response))
        }
        if accept, decoded.token == nil || decoded.livekitUrl == nil {
            #if DEBUG
            print(
                """
                [TradeTraxs Broadcast] invite/respond missing token \
                endpoint=POST /api/livekit/broadcast/invite/respond \
                status=\(response.statusCode) \
                sessionId=\(decoded.broadcastSessionId ?? "nil") \
                roomId=\(decoded.roomId ?? "nil")
                """
            )
            #endif
            throw AppError.unknown(message: decoded.error ?? "Could not mint speaker token.")
        }
        #if DEBUG
        if accept {
            print(
                """
                [TradeTraxs Broadcast] invite/respond ok \
                endpoint=POST /api/livekit/broadcast/invite/respond \
                status=\(response.statusCode) \
                sessionId=\(decoded.broadcastSessionId ?? "nil") \
                roomId=\(decoded.roomId ?? "nil") \
                role=\(decoded.role ?? "nil") \
                canPublish=\(decoded.canPublish.map { String($0) } ?? "nil")
                """
            )
        }
        #endif
        return decoded
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

    private func decodeSuccessBody<T: Decodable>(
        _ type: T.Type,
        response: HTTPResponse,
        path: String,
        method: HTTPMethod,
        requiresAuthentication: Bool
    ) throws -> T {
        #if DEBUG
        LiveKitBFFResponse.log(
            path: path,
            method: method,
            requiresAuthentication: requiresAuthentication,
            response: response
        )
        #endif
        if LiveKitBFFResponse.looksLikeHTML(response) {
            throw AppError.unknown(message: LiveKitBFFResponse.nonJSONMessage(path: path, response: response))
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: decodeAPIError(response))
        }
        do {
            return try transport.decoder.decode(type, from: response)
        } catch let network as NetworkError {
            throw AppError.transport(network)
        } catch {
            throw AppError.unknown(
                message: "Could not read JSON from \(path) (HTTP \(response.statusCode))."
            )
        }
    }

    private func decodeError(_ response: HTTPResponse) -> String {
        if LiveKitBFFResponse.looksLikeHTML(response) {
            return LiveKitBFFResponse.nonJSONMessage(
                path: response.httpURLResponse.url?.path ?? "/api/livekit",
                response: response
            )
        }
        return decodeAPIError(response)
    }

    private func decodeAPIError(_ response: HTTPResponse) -> String {
        struct Err: Decodable { var error: String? }
        if let parsed = try? transport.decoder.decode(Err.self, from: response),
           let message = parsed.error?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty
        {
            return "(\(response.statusCode)) \(message)"
        }
        if response.statusCode == 401 {
            return "Sign in again to use livestream features."
        }
        if response.statusCode == 404 {
            return "This livestream session is no longer available."
        }
        let body = String(data: response.data, encoding: .utf8) ?? ""
        if body.isEmpty {
            return "Broadcast request failed (HTTP \(response.statusCode))."
        }
        return "Broadcast request failed (HTTP \(response.statusCode))."
    }
}
