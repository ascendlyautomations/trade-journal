import Foundation

nonisolated struct RoomRpcBootstrapRepository: RoomsBootstrapProviding {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadRoomBootstrap(
        roomID: String,
        cursor: String?
    ) async throws -> RoomsBootstrapV1 {
        try await loadRoomBootstrap(
            roomID: roomID,
            sectionID: cursor,
            messageLimit: 50,
            markRead: true
        )
    }

    func loadRoomBootstrap(
        roomID: String,
        sectionID: String?,
        messageLimit: Int,
        markRead: Bool
    ) async throws -> RoomsBootstrapV1 {
        let args = RoomRpcArguments(
            p_room_id: roomID,
            p_section_id: sectionID,
            p_message_limit: messageLimit,
            p_mark_read: markRead
        )
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .room,
            argumentsJSON: body,
            as: RoomsBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.rooms.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

private nonisolated struct RoomRpcArguments: Encodable, Sendable {
    var p_room_id: String
    var p_section_id: String?
    var p_message_limit: Int
    var p_mark_read: Bool

    enum CodingKeys: String, CodingKey {
        case p_room_id
        case p_section_id
        case p_message_limit
        case p_mark_read
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_room_id, forKey: .p_room_id)
        if let p_section_id, !p_section_id.isEmpty {
            try container.encode(p_section_id, forKey: .p_section_id)
        } else {
            try container.encodeNil(forKey: .p_section_id)
        }
        try container.encode(p_message_limit, forKey: .p_message_limit)
        try container.encode(p_mark_read, forKey: .p_mark_read)
    }
}

enum RoomBootstrapLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
    }

    @MainActor
    static func load(
        roomID: RoomID,
        viewerID: ProfileID,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache
    ) async throws -> RoomBootstrapApplier.Applied {
        guard BackendV2FeatureFlags.isEnabled(.rooms) else {
            throw LoaderError.flagOff
        }

        let rpcName = BackendV2Versioning.RPCName.room.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue) {
            throw LoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.room(
            viewerID: viewerID.rawValue,
            roomID: roomID.rawValue,
            sectionID: nil
        )
        let bootstrap: RoomsBootstrapV1
        do {
            let data = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                let repo = RoomRpcBootstrapRepository(rpc: rpc)
                let value = try await repo.loadRoomBootstrap(
                    roomID: roomID.rawValue,
                    sectionID: nil,
                    messageLimit: 50,
                    markRead: true
                )
                return try JSONEncoder().encode(value)
            }
            bootstrap = try JSONDecoder().decode(RoomsBootstrapV1.self, from: data)
            try bootstrap.validateContractVersion()
        } catch {
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                await BackendV2RpcAvailability.shared.markUnavailable(
                    rpcName: rpcName,
                    viewerID: viewerID.rawValue
                )
                throw LoaderError.rpcUnavailable
            }
            throw error
        }

        return try RoomBootstrapApplier.apply(
            bootstrap,
            roomID: roomID,
            viewerID: viewerID,
            detailCache: detailCache
        )
    }
}
