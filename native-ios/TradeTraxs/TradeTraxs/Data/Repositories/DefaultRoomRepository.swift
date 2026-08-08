import Foundation

nonisolated struct DefaultRoomRepository: RoomRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    init(supabase: SupabaseInfrastructure, cache: CacheStack = .placeholder()) {
        self.supabase = supabase
        self.cache = cache
    }

    func room(id: RoomID) async throws -> TradeRoom {
        let dto: RoomDTO.Room = try await supabase.database.selectOne(
            RoomDTO.Room.self,
            from: "rooms",
            query: [SupabaseQuery.select("*"), SupabaseQuery.eq("id", id.rawValue)]
        )
        return try mapRoom(dto)
    }

    func rooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        let rows: [RoomDTO.Room] = try await supabase.database.select(
            RoomDTO.Room.self,
            from: "rooms",
            query: SupabaseQuery.page(page) + [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("owner_id", profileID.rawValue),
            ]
        )
        let items = try rows.map(mapRoom)
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.created_at }
        )
    }

    func membership(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership? {
        let rows: [RoomDTO.Membership] = try await supabase.database.select(
            RoomDTO.Membership.self,
            from: "room_members",
            query: [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("room_id", roomID.rawValue),
                SupabaseQuery.eq("user_id", profileID.rawValue),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard let row = rows.first else { return nil }
        return mapMembership(row)
    }

    func join(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership {
        struct Body: Encodable, Decodable {
            var room_id: String
            var user_id: String
        }
        let body = Body(room_id: roomID.rawValue, user_id: profileID.rawValue)
        let row: RoomDTO.Membership = try await supabase.database.insert(
            body,
            into: "room_members",
            returning: RoomDTO.Membership.self
        )
        return mapMembership(row) ?? RoomMembership(
            roomID: roomID,
            profileID: profileID,
            role: .member,
            joinedAt: Date(),
            notificationsEnabled: true
        )
    }

    func leave(roomID: RoomID, profileID: ProfileID) async throws {
        try await supabase.database.delete(
            from: "room_members",
            query: [
                SupabaseQuery.eq("room_id", roomID.rawValue),
                SupabaseQuery.eq("user_id", profileID.rawValue),
            ]
        )
    }

    func messages(roomID: RoomID, page: PageRequest) async throws -> CursorPage<RoomMessage> {
        let rows: [RoomDTO.Message] = try await supabase.database.select(
            RoomDTO.Message.self,
            from: "room_messages",
            query: SupabaseQuery.page(page) + [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("room_id", roomID.rawValue),
            ]
        )
        let items = rows.compactMap(mapMessage)
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.created_at }
        )
    }

    func send(_ message: RoomMessage) async throws -> RoomMessage {
        struct Body: Encodable {
            var room_id: String
            var sender_id: String
            var content: String?
        }
        let body = Body(
            room_id: message.roomID.rawValue,
            sender_id: message.senderProfileID.rawValue,
            content: message.body
        )
        let dto: RoomDTO.Message = try await supabase.database.insert(
            body,
            into: "room_messages",
            returning: RoomDTO.Message.self
        )
        guard let mapped = mapMessage(dto) else { return message }
        return mapped
    }

    func moderate(
        roomID: RoomID,
        messageID: RoomMessageID?,
        targetProfileID: ProfileID?,
        action: RoomModerationAction
    ) async throws {
        switch action {
        case .pin:
            guard let messageID else { return }
            struct Body: Encodable { var is_pinned: Bool }
            _ = try await supabase.database.update(
                Body(is_pinned: true),
                table: "room_messages",
                query: [
                    SupabaseQuery.eq("id", messageID.rawValue),
                    SupabaseQuery.eq("room_id", roomID.rawValue),
                ],
                returning: RoomDTO.Message.self
            )
        case .remove:
            if let messageID {
                try await supabase.database.delete(
                    from: "room_messages",
                    query: [
                        SupabaseQuery.eq("id", messageID.rawValue),
                        SupabaseQuery.eq("room_id", roomID.rawValue),
                    ]
                )
            }
        case .mute, .ban:
            _ = targetProfileID
            // Moderation side-effects are enforced server-side / via future RPCs.
            break
        }
    }

    private func mapRoom(_ dto: RoomDTO.Room) throws -> TradeRoom {
        guard let id = dto.id else { throw MappingError.missingField("id") }
        let owner = dto.owner_id ?? dto.owner_profile_id
        guard let owner else { throw MappingError.missingField("owner_id") }
        guard let name = dto.name else { throw MappingError.missingField("name") }
        return TradeRoom(
            id: RoomID(id),
            ownerProfileID: ProfileID(owner),
            name: name,
            slug: dto.slug ?? id,
            description: dto.description,
            image: dto.image_url.map { MediaReference(id: $0, kind: .image, altText: nil) },
            memberCount: dto.member_count ?? 0,
            showsOnProfile: dto.show_on_profile ?? true,
            createdAt: ISO8601.date(from: dto.created_at) ?? Date()
        )
    }

    private func mapMembership(_ dto: RoomDTO.Membership) -> RoomMembership? {
        guard let roomID = dto.room_id, let userID = dto.user_id else { return nil }
        return RoomMembership(
            roomID: RoomID(roomID),
            profileID: ProfileID(userID),
            role: RoomMemberRole(rawValue: dto.role ?? "") ?? .member,
            joinedAt: ISO8601.date(from: dto.joined_at) ?? Date(),
            notificationsEnabled: true
        )
    }

    private func mapMessage(_ dto: RoomDTO.Message) -> RoomMessage? {
        guard let id = dto.id, let roomID = dto.room_id else { return nil }
        let sender = dto.sender_id ?? dto.sender_profile_id
        guard let sender else { return nil }
        return RoomMessage(
            id: RoomMessageID(id),
            roomID: RoomID(roomID),
            senderProfileID: ProfileID(sender),
            body: dto.body ?? dto.content,
            attachedTradeID: nil,
            media: [],
            parentMessageID: nil,
            isPinned: dto.is_pinned ?? false,
            createdAt: ISO8601.date(from: dto.created_at) ?? Date()
        )
    }
}
