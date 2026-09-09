import Foundation

nonisolated struct DefaultRoomRepository: RoomRepository, RoomManagementRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    /// Exact web Community `loadMemberRooms` embed (`app/community/page.tsx`).
    /// Do not request `member_count` — that column does not exist on `rooms`.
    private static let memberRoomSelect = """
    room_id,room:rooms!room_members_room_id_fkey(\
    id,name,description,slug,image_url,owner_user_id,show_on_profile,is_private,category,discovery_tags,join_policy,rules,\
    members_can_message,members_can_share_trades,members_can_share_media,room_kind)
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

    func createRoom(
        request: RoomCreateRequest,
        ownerProfileID: ProfileID,
        ownerUsername: String
    ) async throws -> TradeRoom {
        struct ChannelWire: Encodable, Sendable {
            var name: String
        }

        struct Params: Encodable, Sendable {
            var p_name: String
            var p_description: String?
            var p_image_url: String?
            var p_show_on_profile: Bool
            var p_is_private: Bool
            var p_category: String?
            var p_discovery_tags: [String]
            var p_join_policy: String
            var p_rules: String?
            var p_members_can_message: Bool
            var p_members_can_share_trades: Bool
            var p_members_can_share_media: Bool
            var p_channels: [ChannelWire]
        }

        let configuration = request.configuration
        if let validationError = TradeRoomConfigurationValidation.validate(configuration) {
            throw DomainError.businessRule(.message(validationError))
        }

        let channels = configuration.channels.map {
            ChannelWire(name: TradeRoomConfigurationValidation.normalizedChannelName($0.name))
        }

        let params = Params(
            p_name: configuration.trimmedName,
            p_description: configuration.trimmedDescription,
            p_image_url: configuration.imageURL,
            p_show_on_profile: configuration.showsOnProfile,
            p_is_private: configuration.visibility == .private,
            p_category: configuration.category?.rawValue,
            p_discovery_tags: configuration.discoveryTags,
            p_join_policy: configuration.effectiveJoinPolicy.rawValue,
            p_rules: configuration.trimmedRules,
            p_members_can_message: configuration.membersCanMessage,
            p_members_can_share_trades: configuration.membersCanShareTrades,
            p_members_can_share_media: configuration.membersCanShareMedia,
            p_channels: channels
        )

        let data = try await supabase.database.rpcData(
            functionName: "rpc_v1_create_trade_room",
            parametersJSON: try JSONEncoder().encode(params)
        )
        let dto = try JSONDecoder().decode(RoomDTO.Room.self, from: data)
        var room = try mapRoom(dto)
        room.memberCount = dto.member_count ?? 1
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

    func requestJoin(roomID: RoomID) async throws -> TradeRoomJoinRequestState {
        struct Params: Encodable { var p_room_id: String }
        struct Response: Decodable {
            var id: String?
            var status: String?
        }
        let data = try await supabase.database.rpcData(
            functionName: "rpc_v1_request_trade_room_join",
            parametersJSON: try JSONEncoder().encode(Params(p_room_id: roomID.rawValue))
        )
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let status = TradeRoomJoinRequestState.parse(response.status) else {
            throw MappingError.missingField("status")
        }
        if status == .pending, let requestID = response.id {
            await TradeRoomJoinRequestNotificationClient(transport: supabase.transport)
                .notifyAfterJoinRequest(roomID: roomID, requestID: requestID)
        }
        return status
    }

    func viewerJoinRequest(roomID: RoomID) async throws -> TradeRoomJoinRequestState? {
        struct Params: Encodable { var p_room_id: String }
        struct Response: Decodable {
            var status: String?
        }
        let data = try await supabase.database.rpcData(
            functionName: "rpc_v1_viewer_trade_room_join_request",
            parametersJSON: try JSONEncoder().encode(Params(p_room_id: roomID.rawValue))
        )
        let response = try JSONDecoder().decode(Response.self, from: data)
        return TradeRoomJoinRequestState.parse(response.status)
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

        if let shareType = message.shareType,
           let content = message.body,
           SharedContentRoomMessageSupport.isStructuredShare(type: shareType, content: content)
        {
            struct ContentShareBody: Encodable {
                var room_id: String
                var user_id: String
                var type: String
                var content: String
                var section_id: String?
            }
            let body = ContentShareBody(
                room_id: message.roomID.rawValue,
                user_id: message.senderProfileID.rawValue,
                type: shareType,
                content: content,
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

        if let content = message.body,
           StoryShareMessageSupport.isStoryShare(type: StoryShareMessageSupport.messageType, content: content)
        {
            struct StoryShareBody: Encodable {
                var room_id: String
                var user_id: String
                var type: String
                var content: String
                var section_id: String?
            }
            let body = StoryShareBody(
                room_id: message.roomID.rawValue,
                user_id: message.senderProfileID.rawValue,
                type: StoryShareMessageSupport.messageType,
                content: content,
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
        guard let name = dto.name else { throw MappingError.missingField("name") }
        let roomKind = TradeRoomKind.parse(dto.room_kind)
        let owner = dto.owner_user_id ?? dto.owner_id ?? dto.owner_profile_id
        let ownerProfileID: ProfileID
        if let owner {
            ownerProfileID = ProfileID(owner)
        } else if roomKind == .official {
            // System-owned official rooms have no profile owner — use stable room-scoped placeholder.
            ownerProfileID = ProfileID("official.\(id)")
        } else {
            throw MappingError.missingField("owner_user_id")
        }
        let category = dto.category.flatMap { TradeRoomCategory(rawValue: $0) }
        let joinPolicy = TradeRoomJoinPolicy(rawValue: dto.join_policy ?? "") ?? .open
        return TradeRoom(
            id: RoomID(id),
            ownerProfileID: ownerProfileID,
            name: name,
            slug: dto.slug ?? id,
            description: dto.description,
            image: Self.nonEmptyImageReference(dto.image_url),
            memberCount: dto.member_count,
            showsOnProfile: dto.show_on_profile ?? true,
            isPrivate: dto.is_private ?? false,
            category: category,
            discoveryTags: dto.discovery_tags ?? [],
            joinPolicy: joinPolicy,
            rules: dto.rules,
            membersCanMessage: dto.members_can_message ?? true,
            membersCanShareTrades: dto.members_can_share_trades ?? true,
            membersCanShareMedia: dto.members_can_share_media ?? true,
            roomKind: roomKind,
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
        let rawContent = dto.body ?? dto.content ?? ""
        if dto.type?.lowercased() == StoryShareMessageSupport.messageType
            || StoryShareMessageSupport.isStoryShare(type: dto.type, content: rawContent)
        {
            return RoomMessage(
                id: RoomMessageID(id),
                roomID: RoomID(roomID),
                senderProfileID: ProfileID(sender),
                body: rawContent,
                attachedTradeID: nil,
                media: [],
                parentMessageID: dto.parent_message_id.map { RoomMessageID($0) },
                channelID: dto.section_id.map { RoomChannelID($0) },
                isPinned: dto.is_pinned ?? false,
                createdAt: ISO8601.date(from: dto.created_at) ?? Date(),
                reactions: (dto.room_message_reactions ?? []).compactMap {
                    mapReaction($0, fallbackMessageID: RoomMessageID(id))
                }
            )
        }
        if SharedContentRoomMessageSupport.isStructuredShare(type: dto.type, content: rawContent) {
            return RoomMessage(
                id: RoomMessageID(id),
                roomID: RoomID(roomID),
                senderProfileID: ProfileID(sender),
                body: rawContent,
                attachedTradeID: nil,
                media: [],
                parentMessageID: dto.parent_message_id.map { RoomMessageID($0) },
                channelID: dto.section_id.map { RoomChannelID($0) },
                isPinned: dto.is_pinned ?? false,
                createdAt: ISO8601.date(from: dto.created_at) ?? Date(),
                shareType: dto.type,
                reactions: (dto.room_message_reactions ?? []).compactMap {
                    mapReaction($0, fallbackMessageID: RoomMessageID(id))
                }
            )
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

    /// Web parity: `loadManageMembers` in `app/community/page.tsx`.
    private static let managedMemberSelect = """
    user_id,created_at,profiles(id,username,name,avatar_url)
    """

    private static let banSelect = """
    id,user_id,created_at,profiles!room_bans_user_id_fkey(id,username,name,avatar_url)
    """

    func createChannel(roomID: RoomID, request: RoomChannelCreateRequest) async throws -> RoomChannel {
        let existing = try await channels(roomID: roomID)
        guard existing.count < RoomChannelValidation.maxCount else {
            throw DomainError.businessRule(.message("Max \(RoomChannelValidation.maxCount) channels allowed."))
        }
        let trimmed = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainError.businessRule(.message("Channel name cannot be empty."))
        }
        guard trimmed.count <= RoomChannelValidation.nameMaxLength else {
            throw DomainError.businessRule(.message("Channel name is too long."))
        }
        let normalized = trimmed.lowercased()
        if existing.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }) {
            throw DomainError.businessRule(.message("A channel with that name already exists."))
        }
        let nextPosition = (existing.map(\.position).max() ?? 0) + 1
        struct Body: Encodable {
            var room_id: String
            var name: String
            var position: Int
            var allow_members_chat: Bool
        }
        let dto: RoomDTO.Channel = try await supabase.database.insert(
            Body(
                room_id: roomID.rawValue,
                name: trimmed,
                position: nextPosition,
                allow_members_chat: request.allowMembersChat
            ),
            into: "room_sections",
            returning: RoomDTO.Channel.self
        )
        guard let channel = mapChannel(dto) else {
            throw MappingError.missingField("room_sections.id")
        }
        return channel
    }

    func updateChannel(channelID: RoomChannelID, request: RoomChannelUpdateRequest) async throws -> RoomChannel {
        struct Body: Encodable {
            var name: String?
            var allow_members_chat: Bool?
            var position: Int?
        }
        let dto: RoomDTO.Channel = try await supabase.database.update(
            Body(
                name: request.name,
                allow_members_chat: request.allowMembersChat,
                position: request.position
            ),
            table: "room_sections",
            query: [SupabaseQuery.eq("id", channelID.rawValue)],
            returning: RoomDTO.Channel.self
        )
        guard let channel = mapChannel(dto) else {
            throw MappingError.missingField("room_sections.id")
        }
        return channel
    }

    func channelMessageCount(
        roomID: RoomID,
        channelID: RoomChannelID,
        channelName: String
    ) async throws -> Int {
        try await supabase.database.count(
            from: "room_messages",
            query: sectionMessageQuery(roomID: roomID, channelID: channelID, channelName: channelName)
        )
    }

    func deleteChannel(roomID: RoomID, channelID: RoomChannelID, channelName: String) async throws {
        let existing = try await channels(roomID: roomID)
        guard existing.count > RoomChannelValidation.minCount else {
            throw DomainError.businessRule(.message("You must have at least one channel."))
        }
        try await supabase.database.delete(
            from: "room_messages",
            query: sectionMessageQuery(roomID: roomID, channelID: channelID, channelName: channelName)
        )
        try await supabase.database.delete(
            from: "room_sections",
            query: [SupabaseQuery.eq("id", channelID.rawValue)]
        )
    }

    private func sectionMessageQuery(
        roomID: RoomID,
        channelID: RoomChannelID,
        channelName: String
    ) -> [URLQueryItem] {
        var query = [SupabaseQuery.eq("room_id", roomID.rawValue)]
        let nameLower = channelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if nameLower == "general" {
            query.append(
                URLQueryItem(
                    name: "or",
                    value: "(section_id.eq.\(channelID.rawValue),section_id.is.null)"
                )
            )
        } else {
            query.append(SupabaseQuery.eq("section_id", channelID.rawValue))
        }
        return query
    }

    func updateRoom(roomID: RoomID, request: RoomUpdateRequest) async throws -> TradeRoom {
        struct Body: Encodable {
            var name: String?
            var description: String?
            var image_url: String?
            var show_on_profile: Bool?
            var is_private: Bool?
            var category: String?
            var discovery_tags: [String]?
            var join_policy: String?
            var rules: String?
            var members_can_message: Bool?
            var members_can_share_trades: Bool?
            var members_can_share_media: Bool?
        }
        let body = Body(
            name: request.name,
            description: request.description,
            image_url: request.imageURL,
            show_on_profile: request.showsOnProfile,
            is_private: request.isPrivate,
            category: request.category?.rawValue,
            discovery_tags: request.discoveryTags,
            join_policy: request.joinPolicy?.rawValue,
            rules: request.rules,
            members_can_message: request.membersCanMessage,
            members_can_share_trades: request.membersCanShareTrades,
            members_can_share_media: request.membersCanShareMedia
        )
        let dto: RoomDTO.Room = try await supabase.database.update(
            body,
            table: "rooms",
            query: [SupabaseQuery.eq("id", roomID.rawValue)],
            returning: RoomDTO.Room.self
        )
        return try mapRoom(dto)
    }

    func managedMembers(roomID: RoomID, ownerProfileID: ProfileID) async throws -> [RoomManagedMember] {
        let members = try await activeMembers(roomID: roomID, ownerProfileID: ownerProfileID)
        let tagsByUser = (try? await memberTagsByUser(roomID: roomID)) ?? [:]
        return members.map { member in
            var updated = member
            updated.tags = tagsByUser[member.profile.id] ?? []
            return updated
        }
    }

    func activeMembers(roomID: RoomID, ownerProfileID: ProfileID) async throws -> [RoomManagedMember] {
        let rows = try await fetchActiveMemberRows(roomID: roomID)
        return mapActiveMemberRows(rows, ownerProfileID: ownerProfileID, tagsByUser: [:])
    }

    private func fetchActiveMemberRows(roomID: RoomID) async throws -> [RoomDTO.ManagedMemberRow] {
        let key = "room.activeMemberRows:\(roomID.rawValue)"
        return try await RepositoryRequestFlight.shared.coalesce(
            key: key,
            resource: "room_members"
        ) { [self] in
            let query = [
                SupabaseQuery.select(Self.managedMemberSelect),
                SupabaseQuery.eq("room_id", roomID.rawValue),
                URLQueryItem(name: "left_at", value: "is.null"),
            ]
            let rows: [RoomDTO.ManagedMemberRow] = try await supabase.database.select(
                RoomDTO.ManagedMemberRow.self,
                from: "room_members",
                query: query
            )
            #if DEBUG
            RoomMembersLoadProbe.membershipsReturned(count: rows.count)
            #endif
            return rows
        }
    }

    private func mapActiveMemberRows(
        _ rows: [RoomDTO.ManagedMemberRow],
        ownerProfileID: ProfileID,
        tagsByUser: [ProfileID: [RoomMemberTag]]
    ) -> [RoomManagedMember] {
        rows.compactMap { row -> RoomManagedMember? in
            guard let userID = row.user_id else { return nil }
            let profileID = ProfileID(userID)
            let profile = mapMemberProfile(row.profiles, userID: userID)
            let role: RoomMemberRole = profileID == ownerProfileID ? .owner : .member
            return RoomManagedMember(
                profile: profile,
                role: role,
                joinedAt: ISO8601.date(from: row.membershipJoinedAt),
                tags: tagsByUser[profileID] ?? []
            )
        }
        .sorted { lhs, rhs in
            managementRoleRank(lhs.role) < managementRoleRank(rhs.role)
                || (lhs.role == rhs.role
                    && lhs.profile.displayName.localizedCaseInsensitiveCompare(rhs.profile.displayName)
                        == .orderedAscending)
        }
    }

    private func memberTagsByUser(roomID: RoomID) async throws -> [ProfileID: [RoomMemberTag]] {
        let tags = try await memberTags(roomID: roomID)
        let assignments = try await memberTagAssignments(roomID: roomID)
        let tagByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        return Dictionary(grouping: assignments, by: \.profileID)
            .mapValues { assignments in
                assignments.compactMap { tagByID[$0.tagID] }
            }
    }

    func bannedMembers(roomID: RoomID) async throws -> [RoomBanRecord] {
        let rows: [RoomDTO.BanRow] = try await supabase.database.select(
            RoomDTO.BanRow.self,
            from: "room_bans",
            query: [
                SupabaseQuery.select(Self.banSelect),
                SupabaseQuery.eq("room_id", roomID.rawValue),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]
        )
        return rows.compactMap { row in
            guard let id = row.id,
                  let userID = row.user_id,
                  let profile = mapEmbeddedProfile(row.profiles)
            else { return nil }
            return RoomBanRecord(
                id: id,
                roomID: roomID,
                profileID: ProfileID(userID),
                profile: profile,
                bannedAt: ISO8601.date(from: row.created_at) ?? .now
            )
        }
    }

    func removeMember(roomID: RoomID, profileID: ProfileID) async throws {
        struct Body: Encodable { var left_at: String }
        _ = try await supabase.database.update(
            Body(left_at: ISO8601.string(from: Date())),
            table: "room_members",
            query: [
                SupabaseQuery.eq("room_id", roomID.rawValue),
                SupabaseQuery.eq("user_id", profileID.rawValue),
                URLQueryItem(name: "left_at", value: "is.null"),
            ],
            returning: RoomDTO.Membership.self
        )
    }

    func banMember(roomID: RoomID, profileID: ProfileID, bannedBy: ProfileID) async throws {
        struct BanBody: Encodable {
            var room_id: String
            var user_id: String
            var banned_by: String
        }
        struct BanRow: Decodable { var id: String? }
        _ = try? await supabase.database.insert(
            BanBody(
                room_id: roomID.rawValue,
                user_id: profileID.rawValue,
                banned_by: bannedBy.rawValue
            ),
            into: "room_bans",
            returning: BanRow.self
        )
        try await removeMember(roomID: roomID, profileID: profileID)
    }

    func unbanMember(roomID: RoomID, banID: String) async throws {
        try await supabase.database.delete(
            from: "room_bans",
            query: [
                SupabaseQuery.eq("id", banID),
                SupabaseQuery.eq("room_id", roomID.rawValue),
            ]
        )
    }

    func ensureDefaultMemberTags(roomID: RoomID) async throws {
        struct Params: Encodable { var p_room_id: String }
        let data = try JSONEncoder().encode(Params(p_room_id: roomID.rawValue))
        _ = try await supabase.database.rpcData(
            functionName: "ensure_room_member_tags_defaults",
            parametersJSON: data
        )
    }

    func memberTags(roomID: RoomID) async throws -> [RoomMemberTag] {
        let rows: [RoomDTO.MemberTag] = try await supabase.database.select(
            RoomDTO.MemberTag.self,
            from: "room_member_tags",
            query: [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("room_id", roomID.rawValue),
                URLQueryItem(name: "order", value: "name.asc"),
            ]
        )
        return rows.compactMap(mapMemberTag)
    }

    func createMemberTag(
        roomID: RoomID,
        name: String,
        colorKey: String,
        createdBy: ProfileID
    ) async throws -> RoomMemberTag {
        struct Body: Encodable {
            var room_id: String
            var name: String
            var color_key: String
            var is_preset: Bool
            var created_by: String
        }
        let dto: RoomDTO.MemberTag = try await supabase.database.insert(
            Body(
                room_id: roomID.rawValue,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                color_key: colorKey,
                is_preset: false,
                created_by: createdBy.rawValue
            ),
            into: "room_member_tags",
            returning: RoomDTO.MemberTag.self
        )
        guard let tag = mapMemberTag(dto) else {
            throw MappingError.missingField("room_member_tags.id")
        }
        return tag
    }

    func updateMemberTag(_ tag: RoomMemberTag) async throws -> RoomMemberTag {
        struct Body: Encodable {
            var name: String
            var color_key: String
        }
        let dto: RoomDTO.MemberTag = try await supabase.database.update(
            Body(name: tag.name, color_key: tag.colorKey),
            table: "room_member_tags",
            query: [
                SupabaseQuery.eq("id", tag.id.rawValue),
                SupabaseQuery.eq("room_id", tag.roomID.rawValue),
            ],
            returning: RoomDTO.MemberTag.self
        )
        guard let updated = mapMemberTag(dto) else {
            throw MappingError.missingField("room_member_tags.id")
        }
        return updated
    }

    func deleteMemberTag(tagID: RoomMemberTagID, roomID: RoomID) async throws {
        try await supabase.database.delete(
            from: "room_member_tags",
            query: [
                SupabaseQuery.eq("id", tagID.rawValue),
                SupabaseQuery.eq("room_id", roomID.rawValue),
            ]
        )
    }

    func memberTagAssignments(roomID: RoomID) async throws -> [RoomMemberTagAssignment] {
        let rows: [RoomDTO.TagAssignment] = try await supabase.database.select(
            RoomDTO.TagAssignment.self,
            from: "room_member_tag_assignments",
            query: [
                SupabaseQuery.select("room_id,user_id,tag_id"),
                SupabaseQuery.eq("room_id", roomID.rawValue),
            ]
        )
        return rows.compactMap { row in
            guard let room = row.room_id,
                  let user = row.user_id,
                  let tag = row.tag_id
            else { return nil }
            return RoomMemberTagAssignment(
                roomID: RoomID(room),
                profileID: ProfileID(user),
                tagID: RoomMemberTagID(tag)
            )
        }
    }

    func assignMemberTag(
        roomID: RoomID,
        profileID: ProfileID,
        tagID: RoomMemberTagID
    ) async throws {
        struct Body: Encodable {
            var room_id: String
            var user_id: String
            var tag_id: String
        }
        _ = try await supabase.database.insert(
            Body(
                room_id: roomID.rawValue,
                user_id: profileID.rawValue,
                tag_id: tagID.rawValue
            ),
            into: "room_member_tag_assignments",
            returning: RoomDTO.TagAssignment.self
        )
    }

    func removeMemberTagAssignment(
        roomID: RoomID,
        profileID: ProfileID,
        tagID: RoomMemberTagID
    ) async throws {
        try await supabase.database.delete(
            from: "room_member_tag_assignments",
            query: [
                SupabaseQuery.eq("room_id", roomID.rawValue),
                SupabaseQuery.eq("user_id", profileID.rawValue),
                SupabaseQuery.eq("tag_id", tagID.rawValue),
            ]
        )
    }

    func pendingJoinRequests(roomID: RoomID) async throws -> [RoomJoinRequestRecord] {
        struct Params: Encodable {
            var p_room_id: String
            var p_status: String
        }
        struct ProfileWire: Decodable {
            var id: String?
            var username: String?
            var name: String?
            var avatar_url: String?
        }
        struct RequestWire: Decodable {
            var id: String?
            var room_id: String?
            var user_id: String?
            var status: String?
            var created_at: String?
            var profile: ProfileWire?
        }
        struct Payload: Decodable {
            var requests: [RequestWire]?
        }
        let data = try await supabase.database.rpcData(
            functionName: "rpc_v1_list_trade_room_join_requests",
            parametersJSON: try JSONEncoder().encode(
                Params(p_room_id: roomID.rawValue, p_status: "pending")
            )
        )
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return (payload.requests ?? []).compactMap { wire in
            guard let id = wire.id,
                  let roomRaw = wire.room_id,
                  let userRaw = wire.user_id,
                  let status = TradeRoomJoinRequestState.parse(wire.status)
            else { return nil }
            var profile: Profile?
            if let p = wire.profile,
               let username = p.username?.trimmingCharacters(in: .whitespacesAndNewlines),
               !username.isEmpty,
               let pid = p.id
            {
                let displayName = p.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                profile = Profile(
                    id: ProfileID(pid),
                    userID: UserID(pid),
                    username: username,
                    displayName: (displayName?.isEmpty == false) ? displayName! : username,
                    bio: nil,
                    avatar: p.avatar_url.map { MediaReference(id: $0, kind: .image, altText: nil) },
                    traderType: nil,
                    tradingStyle: nil,
                    primaryMarket: nil,
                    startedTradingAt: nil,
                    isPrivate: false,
                    isCreator: false,
                    createdAt: .now
                )
            }
            return RoomJoinRequestRecord(
                id: id,
                roomID: RoomID(roomRaw),
                profileID: ProfileID(userRaw),
                status: status,
                createdAt: ISO8601.date(from: wire.created_at),
                profile: profile
            )
        }
    }

    func resolveJoinRequest(
        requestID: String,
        action: TradeRoomJoinRequestResolution
    ) async throws {
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }
        struct Body: Encodable { var requestId: String }
        let path = action == .approve
            ? "/api/trade-room-join-requests/approve"
            : "/api/trade-room-join-requests/decline"
        let data = try transport.encodeJSON(Body(requestId: requestID))
        let response = try await transport.send(
            host: .bff,
            path: path,
            method: .post,
            body: data,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: "Join request action failed (\(response.statusCode))")
        }
    }

    private func mapMemberTag(_ dto: RoomDTO.MemberTag) -> RoomMemberTag? {
        guard let id = dto.id,
              let roomID = dto.room_id,
              let name = dto.name
        else { return nil }
        return RoomMemberTag(
            id: RoomMemberTagID(id),
            roomID: RoomID(roomID),
            name: name,
            colorKey: dto.color_key ?? "accent",
            isPreset: dto.is_preset ?? false
        )
    }

    private func mapEmbeddedProfile(_ dto: RoomDTO.EmbeddedProfile?) -> Profile? {
        guard let dto,
              let id = dto.id,
              let username = dto.username?.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty
        else { return nil }
        let displayName = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Profile(
            id: ProfileID(id),
            userID: UserID(id),
            username: username,
            displayName: (displayName?.isEmpty == false) ? displayName! : username,
            bio: nil,
            avatar: dto.avatar_url.map { MediaReference(id: $0, kind: .image, altText: nil) },
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
    }

    private func mapMemberProfile(_ dto: RoomDTO.EmbeddedProfile?, userID: String) -> Profile {
        if let profile = mapEmbeddedProfile(dto) {
            return profile
        }
        let profileID = ProfileID(userID)
        return Profile(
            id: profileID,
            userID: UserID(userID),
            username: "deleted",
            displayName: "Unknown User",
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
    }

    private func managementRoleRank(_ role: RoomMemberRole) -> Int {
        switch role {
        case .owner: return 0
        case .admin: return 1
        case .member: return 2
        }
    }

    private static func nonEmptyImageReference(_ raw: String?) -> MediaReference? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return MediaReference(id: trimmed, kind: .image, altText: nil)
    }
}
