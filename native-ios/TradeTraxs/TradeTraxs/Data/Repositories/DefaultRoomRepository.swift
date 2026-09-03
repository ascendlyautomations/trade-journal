import Foundation

nonisolated struct DefaultRoomRepository: RoomRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    /// Exact web Community `loadMemberRooms` embed (`app/community/page.tsx`).
    /// Do not request `member_count` — that column does not exist on `rooms`.
    private static let memberRoomSelect = """
    room_id,room:rooms!room_members_room_id_fkey(\
    id,name,description,slug,image_url,owner_user_id,show_on_profile)
    """

    /// Web `lib/roomMessageSelect.ts` — explicit embed hint avoids PGRST201.
    private static let messageSelect = """
    id,room_id,user_id,seen_by,pinned,section_id,parent_message_id,type,trade_id,content,image_url,created_at,\
    room_message_reactions!room_message_reactions_message_room_fkey(id,message_id,user_id,reaction)
    """

    init(supabase: SupabaseInfrastructure, cache: CacheStack = .placeholder()) {
        self.supabase = supabase
        self.cache = cache
    }

    func room(id: RoomID) async throws -> TradeRoom {
        // Push / community deep links may pass slug in the `room` query — resolve id then slug.
        let dto: RoomDTO.Room
        if let byID = try? await supabase.database.selectOne(
            RoomDTO.Room.self,
            from: "rooms",
            query: [SupabaseQuery.select("*"), SupabaseQuery.eq("id", id.rawValue)]
        ) {
            dto = byID
        } else {
            dto = try await supabase.database.selectOne(
                RoomDTO.Room.self,
                from: "rooms",
                query: [SupabaseQuery.select("*"), SupabaseQuery.eq("slug", id.rawValue)]
            )
        }
        var room = try mapRoom(dto)
        // Exact web `loadMemberStats` active count:
        // room_members where room_id = ? and left_at is null (count exact).
        if let active = try? await supabase.database.count(
            from: "room_members",
            query: [
                SupabaseQuery.eq("room_id", room.id.rawValue),
                URLQueryItem(name: "left_at", value: "is.null"),
            ]
        ) {
            room.memberCount = active
        }
        return room
    }

    func rooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        // Exact web Profile ownership query (`app/profile/[id]/page.tsx`):
        // rooms where owner_user_id = profile.id (not owner_id).
        let cursor = page.cursor ?? "-"
        let key = "rooms.owned:\(profileID.rawValue):limit=\(page.limit):cursor=\(cursor)"
        return try await RepositoryRequestFlight.shared.coalesce(
            key: key,
            resource: "rooms.owned"
        ) { [self] in
            let rows: [RoomDTO.Room] = try await supabase.database.select(
                RoomDTO.Room.self,
                from: "rooms",
                query: SupabaseQuery.page(page) + [
                    SupabaseQuery.select("*"),
                    SupabaseQuery.eq("owner_user_id", profileID.rawValue),
                ]
            )
            let items = try rows.map(mapRoom)
            return CursorPage(
                items: items,
                nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.created_at }
            )
        }
    }

    func memberRooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        let rows: [RoomDTO.MemberRoomRow] = try await supabase.database.select(
            RoomDTO.MemberRoomRow.self,
            from: "room_members",
            query: [
                SupabaseQuery.select(Self.memberRoomSelect),
                SupabaseQuery.eq("user_id", profileID.rawValue),
                URLQueryItem(name: "left_at", value: "is.null"),
            ]
        )
        let items = rows.compactMap { row -> TradeRoom? in
            guard let room = row.room else { return nil }
            return try? mapRoom(room)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let limited = Array(items.prefix(page.limit))
        return CursorPage(
            items: limited,
            nextCursor: items.count > page.limit ? limited.last?.id.rawValue : nil
        )
    }

    func activeMemberCounts(for roomIDs: [RoomID]) async throws -> [RoomID: Int] {
        let unique = Array(Set(roomIDs.map(\.rawValue))).filter { !$0.isEmpty }
        guard !unique.isEmpty else { return [:] }

        struct Row: Decodable, Sendable {
            var room_id: String?
        }

        let rows: [Row] = try await supabase.database.select(
            Row.self,
            from: "room_members",
            query: [
                SupabaseQuery.select("room_id"),
                SupabaseQuery.isIn("room_id", unique),
                URLQueryItem(name: "left_at", value: "is.null"),
            ]
        )

        var counts: [RoomID: Int] = [:]
        for row in rows {
            guard let raw = row.room_id else { continue }
            let roomID = RoomID(raw)
            counts[roomID, default: 0] += 1
        }
        for roomID in roomIDs {
            counts[roomID] = counts[roomID, default: 0]
        }
        return counts
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

    func channels(roomID: RoomID) async throws -> [RoomChannel] {
        // Exact web Community `loadSections`:
        // room_sections select id, room_id, name, position, allow_members_chat
        // where room_id = ? order by position ascending.
        let rows: [RoomDTO.Channel] = try await supabase.database.select(
            RoomDTO.Channel.self,
            from: "room_sections",
            query: [
                SupabaseQuery.select("id, room_id, name, position, allow_members_chat"),
                SupabaseQuery.eq("room_id", roomID.rawValue),
                URLQueryItem(name: "order", value: "position.asc"),
            ]
        )
        return rows.compactMap(mapChannel)
    }

    func messages(roomID: RoomID, page: PageRequest) async throws -> CursorPage<RoomMessage> {
        try await messages(roomID: roomID, channel: nil, page: page)
    }

    func messages(
        roomID: RoomID,
        channel: RoomChannel?,
        page: PageRequest
    ) async throws -> CursorPage<RoomMessage> {
        // Web `applySectionFiltersToQuery` / `sectionMessageFilter`.
        var query = SupabaseQuery.page(page) + [
            SupabaseQuery.select(Self.messageSelect),
            SupabaseQuery.eq("room_id", roomID.rawValue),
        ]
        if let channel {
            if channel.isGeneral {
                query.append(
                    URLQueryItem(
                        name: "or",
                        value: "(section_id.eq.\(channel.id.rawValue),section_id.is.null)"
                    )
                )
            } else {
                query.append(SupabaseQuery.eq("section_id", channel.id.rawValue))
            }
        }
        let rows: [RoomDTO.Message] = try await supabase.database.select(
            RoomDTO.Message.self,
            from: "room_messages",
            query: query
        )
        let items = rows.compactMap(mapMessage)
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.created_at }
        )
    }

    func send(_ message: RoomMessage) async throws -> RoomMessage {
        // Web community inserts use `user_id` + `section_id` (active channel).
        // Trade shares match `sendTradeMessage`.
        if let tradeID = message.attachedTradeID {
            struct TradeBody: Encodable {
                var room_id: String
                var user_id: String
                var type: String
                var trade_id: String
                var content: String
                var section_id: String?
            }
            let body = TradeBody(
                room_id: message.roomID.rawValue,
                user_id: message.senderProfileID.rawValue,
                type: "trade",
                trade_id: tradeID.rawValue,
                content: "Shared a trade",
                section_id: message.channelID?.rawValue
            )
            let dto: RoomDTO.Message = try await supabase.database.insert(
                body,
                into: "room_messages",
                returning: RoomDTO.Message.self
            )
            guard let mapped = mapMessage(dto) else { return message }
            return mapped
        }

        if let audio = message.media.first(where: { $0.kind == .audio }) {
            struct VoiceBody: Encodable {
                var room_id: String
                var user_id: String
                var type: String
                var content: String
                var audio_url: String
                var audio_duration_ms: Int?
                var section_id: String?
            }
            let durationMs = message.media.first?.altText.flatMap { Double($0) }.map {
                Int(($0 * 1_000).rounded())
            }
            let body = VoiceBody(
                room_id: message.roomID.rawValue,
                user_id: message.senderProfileID.rawValue,
                type: "voice",
                content: "",
                audio_url: audio.id,
                audio_duration_ms: durationMs,
                section_id: message.channelID?.rawValue
            )
            let dto: RoomDTO.Message = try await supabase.database.insert(
                body,
                into: "room_messages",
                returning: RoomDTO.Message.self
            )
            guard let mapped = mapMessage(dto) else { return message }
            return mapped
        }

        struct Body: Encodable {
            var room_id: String
            var user_id: String
            var content: String?
            var type: String
            var section_id: String?
        }
        let body = Body(
            room_id: message.roomID.rawValue,
            user_id: message.senderProfileID.rawValue,
            content: message.body,
            type: message.media.isEmpty ? "text" : "image",
            section_id: message.channelID?.rawValue
        )
        let dto: RoomDTO.Message = try await supabase.database.insert(
            body,
            into: "room_messages",
            returning: RoomDTO.Message.self
        )
        guard let mapped = mapMessage(dto) else { return message }
        return mapped
    }

    func insertMessageReaction(
        roomID: RoomID,
        messageID: RoomMessageID,
        userID: ProfileID,
        reaction: String
    ) async throws -> RoomMessageReaction {
        struct Body: Encodable {
            var message_id: String
            var user_id: String
            var reaction: String
            var room_id: String
        }
        let row: RoomDTO.ReactionRow = try await supabase.database.insert(
            Body(
                message_id: messageID.rawValue,
                user_id: userID.rawValue,
                reaction: reaction,
                room_id: roomID.rawValue
            ),
            into: "room_message_reactions",
            returning: RoomDTO.ReactionRow.self
        )
        guard let mapped = mapReaction(row, fallbackMessageID: messageID) else {
            throw AppError.unknown(message: "Could not update reaction.")
        }
        return mapped
    }

    func deleteMessageReaction(id: String) async throws {
        try await supabase.database.delete(
            from: "room_message_reactions",
            query: [SupabaseQuery.eq("id", id)]
        )
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
        let owner = dto.owner_user_id ?? dto.owner_id ?? dto.owner_profile_id
        guard let owner else { throw MappingError.missingField("owner_user_id") }
        guard let name = dto.name else { throw MappingError.missingField("name") }
        return TradeRoom(
            id: RoomID(id),
            ownerProfileID: ProfileID(owner),
            name: name,
            slug: dto.slug ?? id,
            description: dto.description,
            image: dto.image_url.map { MediaReference(id: $0, kind: .image, altText: nil) },
            memberCount: dto.member_count,
            showsOnProfile: dto.show_on_profile ?? true,
            createdAt: ISO8601.date(from: dto.created_at) ?? Date()
        )
    }

    func unreadCounts(for roomIDs: [RoomID]) async throws -> [RoomID: Int] {
        let raw = roomIDs.map(\.rawValue)
        guard !raw.isEmpty else { return [:] }
        struct Params: Encodable { var p_room_ids: [String] }
        do {
            let data = try await supabase.database.rpcData(
                functionName: "get_room_unread_counts",
                parametersJSON: try JSONEncoder().encode(Params(p_room_ids: raw))
            )
            let rows = try JSONDecoder().decode([RoomDTO.RoomUnreadCountRow].self, from: data)
            var map: [RoomID: Int] = [:]
            for row in rows {
                guard let id = row.room_id else { continue }
                map[RoomID(id)] = row.unread_count ?? 0
            }
            return map
        } catch {
            // Web fail-closed.
            return [:]
        }
    }

    func markRead(roomID: RoomID) async throws {
        // Exact web Community `markAllRoomMessagesSeenForUser` → RPC `mark_room_read`.
        struct Params: Encodable {
            var p_room_id: String
        }
        let data = try JSONEncoder().encode(Params(p_room_id: roomID.rawValue))
        _ = try await supabase.database.rpcData(
            functionName: "mark_room_read",
            parametersJSON: data
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
        let sender = dto.sender_id ?? dto.sender_profile_id ?? dto.user_id
        guard let sender else { return nil }
        let tradeID = dto.trade_id.flatMap { raw -> TradeID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : TradeID(trimmed)
        }
        let imageURL = dto.image_url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let audioURL = dto.audio_url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceDuration = dto.audio_duration_ms.map { Double($0) / 1_000.0 }
        let isVoice = dto.type?.lowercased() == "voice" || !(audioURL?.isEmpty ?? true)
        let media: [MediaReference] = {
            if let audioURL, !audioURL.isEmpty {
                return [MediaReference(id: audioURL, kind: .audio, altText: voiceDuration.map { String($0) })]
            }
            guard let imageURL, !imageURL.isEmpty else { return [] }
            return [MediaReference(id: imageURL, kind: .image, altText: nil)]
        }()
        return RoomMessage(
            id: RoomMessageID(id),
            roomID: RoomID(roomID),
            senderProfileID: ProfileID(sender),
            body: isVoice ? nil : (dto.body ?? dto.content),
            attachedTradeID: tradeID,
            media: media,
            parentMessageID: dto.parent_message_id.map { RoomMessageID($0) },
            channelID: dto.section_id.map { RoomChannelID($0) },
            isPinned: dto.is_pinned ?? false,
            createdAt: ISO8601.date(from: dto.created_at) ?? Date(),
            reactions: (dto.room_message_reactions ?? []).compactMap {
                mapReaction($0, fallbackMessageID: RoomMessageID(id))
            }
        )
    }

    private func mapReaction(
        _ dto: RoomDTO.ReactionRow,
        fallbackMessageID: RoomMessageID
    ) -> RoomMessageReaction? {
        guard let id = dto.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
              let reaction = dto.reaction?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reaction.isEmpty,
              RoomMessageReactionSemantics.supportedEmojis.contains(reaction)
        else { return nil }
        let messageRaw = dto.message_id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageID = messageRaw.flatMap { raw -> RoomMessageID? in
            raw.isEmpty ? nil : RoomMessageID(raw)
        } ?? fallbackMessageID
        guard let userRaw = dto.user_id?.trimmingCharacters(in: .whitespacesAndNewlines), !userRaw.isEmpty
        else { return nil }
        return RoomMessageReaction(
            id: id,
            messageID: messageID,
            userID: ProfileID(userRaw),
            reaction: reaction,
            createdAt: ISO8601.date(from: dto.created_at)
        )
    }

    private func mapChannel(_ dto: RoomDTO.Channel) -> RoomChannel? {
        guard let id = dto.id, let roomID = dto.room_id else { return nil }
        let name = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        return RoomChannel(
            id: RoomChannelID(id),
            roomID: RoomID(roomID),
            name: name,
            position: dto.position ?? 0,
            allowMembersChat: dto.allow_members_chat ?? true
        )
    }
}
