import Foundation
import OSLog

/// Production messaging repository — mirrors web `fetchUserDmConversations` / unread / `ensureDmConversation`.
nonisolated struct DefaultMessageRepository: MessageRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack
    private let session: any SessionProviding

    /// Same select as web `fetchUserDmConversations`.
    private static let conversationSelect = """
    id,is_group,is_pinned,name,avatar_url,last_message,last_message_at,\
    participants:conversation_participants(user_id,profiles(id,username,avatar_url,name))
    """

    init(
        supabase: SupabaseInfrastructure,
        cache: CacheStack = .placeholder(),
        session: any SessionProviding
    ) {
        self.supabase = supabase
        self.cache = cache
        self.session = session
    }

    func conversations(page: PageRequest) async throws -> ConversationListResult {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let viewer = userID.rawValue

        async let membershipTask: [MessageDTO.MembershipRow] = supabase.database.select(
            MessageDTO.MembershipRow.self,
            from: "conversation_participants",
            query: [
                SupabaseQuery.select("conversation_id"),
                SupabaseQuery.eq("user_id", viewer),
            ]
        )
        async let hiddenTask = fetchHiddenBlockedConversationIDs()

        let membershipRows = try await membershipTask
        let hiddenIDs = await hiddenTask

        let conversationIDs = Array(
            Set(
                membershipRows.compactMap(\.conversation_id)
                    .filter { !$0.isEmpty && !hiddenIDs.contains($0) }
            )
        )

        guard !conversationIDs.isEmpty else {
            return ConversationListResult(items: [], nextCursor: nil, embeddedProfiles: [])
        }

        // PostgREST `in.()` batches — keep under URL limits for large inboxes.
        var rows: [MessageDTO.Conversation] = []
        for chunk in conversationIDs.chunked(into: 80) {
            let batch: [MessageDTO.Conversation] = try await supabase.database.select(
                MessageDTO.Conversation.self,
                from: "conversations",
                query: [
                    SupabaseQuery.select(Self.conversationSelect),
                    SupabaseQuery.isIn("id", chunk),
                ]
            )
            rows.append(contentsOf: batch)
        }

        let ids = rows.compactMap(\.id)
        async let unreadTask = fetchUnreadCounts(conversationIDs: ids)
        async let mutedTask = fetchMutedConversationIDs(userID: viewer, conversationIDs: ids)
        let unreadByID = await unreadTask
        let mutedIDs = await mutedTask

        var embedded: [ProfileID: Profile] = [:]
        let mapped = rows.compactMap { dto -> Conversation? in
            guard let id = dto.id else { return nil }
            let muted = mutedIDs.contains(id)
            let unread = muted ? 0 : (unreadByID[id] ?? 0)
            for profile in extractEmbeddedProfiles(from: dto) {
                embedded[profile.id] = profile
            }
            return mapConversation(dto, viewerID: viewer, unreadCount: unread, isMuted: muted)
        }

        let sorted = sortConversations(mapped)
        let limited = Array(sorted.prefix(page.limit))
        let next = sorted.count > page.limit
            ? limited.last?.lastMessageAt.map { ISO8601.string(from: $0) }
            : nil
        return ConversationListResult(
            items: limited,
            nextCursor: next,
            embeddedProfiles: Array(embedded.values)
        )
    }

    func conversation(id: ConversationID) async throws -> Conversation {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let dto: MessageDTO.Conversation = try await supabase.database.selectOne(
            MessageDTO.Conversation.self,
            from: "conversations",
            query: [
                SupabaseQuery.select(Self.conversationSelect),
                SupabaseQuery.eq("id", id.rawValue),
            ]
        )
        let unread = await fetchUnreadCounts(conversationIDs: [id.rawValue])[id.rawValue] ?? 0
        let muted = await fetchMutedConversationIDs(
            userID: userID.rawValue,
            conversationIDs: [id.rawValue]
        ).contains(id.rawValue)
        guard let mapped = mapConversation(
            dto,
            viewerID: userID.rawValue,
            unreadCount: muted ? 0 : unread,
            isMuted: muted
        ) else {
            throw AppError.domain(.notFound(entity: "conversation", id: id.rawValue))
        }
        return mapped
    }

    func messages(
        in conversationID: ConversationID,
        page: PageRequest
    ) async throws -> CursorPage<Message> {
        let rows: [MessageDTO.Message] = try await supabase.database.select(
            MessageDTO.Message.self,
            from: "messages",
            query: SupabaseQuery.page(page) + [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("conversation_id", conversationID.rawValue),
            ]
        )
        let items = try rows.compactMap { row -> Message? in
            if row.deleted_for_everyone == true { return nil }
            return try MessageMapper.mapToDomain(row)
        }
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.created_at }
        )
    }

    func send(_ message: Message) async throws -> Message {
        // Web trade share (`handleSendTrade`): type/trade_id/content null/channel null.
        if message.kind == .tradeShare,
           let tradeID = message.attachments.first?.tradeID ?? message.attachments.compactMap(\.tradeID).first
        {
            return try await sendTradeShare(message, tradeID: tradeID)
        }

        if message.kind == .storyShare, let content = message.body {
            return try await sendStoryShare(message, content: content)
        }

        if message.kind == .voice,
           let audioURL = message.attachments.first?.media.id
        {
            return try await sendVoiceMessage(message, audioURL: audioURL)
        }

        // Exact web `sendMessage` insert shape from `app/messages/[id]/page.tsx`:
        // { conversation_id, sender_id, content, image_url, channel: null, parent_message_id? }
        // RLS `messages_insert_conversation_participant` requires `channel is null`.
        let imageURL = message.attachments.first?.media.id
        let body = DMSendBody(
            conversation_id: message.conversationID.rawValue,
            sender_id: message.senderProfileID.rawValue,
            content: message.body ?? "",
            image_url: imageURL,
            parent_message_id: message.replyToMessageID?.rawValue
        )
        AppLog.networking.info(
            """
            messages.send begin \
            convo=\(SafeInboxLog.hash(message.conversationID.rawValue), privacy: .public) \
            bodyChars=\((message.body ?? "").count, privacy: .public) \
            hasImage=\(imageURL != nil, privacy: .public)
            """
        )
        do {
            // Web: `.insert(sendPayload).select("id").single()` (+ created_at for domain mapping).
            let inserted: DMInsertRow = try await supabase.database.insert(
                body,
                into: "messages",
                query: [SupabaseQuery.select("id,created_at")],
                returning: DMInsertRow.self
            )
            guard let id = inserted.id, !id.isEmpty else {
                throw AppError.unknown(message: "Message insert returned no id")
            }
            AppLog.networking.info(
                "messages.send ok message=\(SafeInboxLog.hash(id), privacy: .public) status=201"
            )
            // Web: `void createDirectMessagePush(supabase, insertedMessage.id)` — push must not
            // gate message persistence. Failures are logged inside the client.
            scheduleDirectMessagePush(messageID: id)
            let createdAt = ISO8601.date(from: inserted.created_at) ?? message.createdAt
            return Message(
                id: MessageID(id),
                conversationID: message.conversationID,
                senderProfileID: message.senderProfileID,
                kind: imageURL == nil ? .text : .media,
                body: message.body ?? "",
                attachments: message.attachments,
                replyToMessageID: message.replyToMessageID,
                createdAt: createdAt,
                isReadByViewer: true
            )
        } catch {
            AppLog.networking.error(
                """
                messages.send failed \
                convo=\(SafeInboxLog.hash(message.conversationID.rawValue), privacy: .public) \
                bodyChars=\((message.body ?? "").count, privacy: .public) \
                error=\(String(describing: error), privacy: .public)
                """
            )
            throw error
        }
    }

    func markRead(conversationID: ConversationID) async throws {
        let data = try JSONEncoder().encode(
            MessageRPCParams.ConversationID(p_conversation_id: conversationID.rawValue)
        )
        _ = try await supabase.database.rpcData(
            functionName: "mark_conversation_read",
            parametersJSON: data
        )
    }

    func markUnread(conversationID: ConversationID) async throws {
        let data = try JSONEncoder().encode(
            MessageRPCParams.ConversationID(p_conversation_id: conversationID.rawValue)
        )
        _ = try await supabase.database.rpcData(
            functionName: "mark_conversation_unread",
            parametersJSON: data
        )
    }

    func createConversation(participantIDs: [ProfileID]) async throws -> Conversation {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let viewerID = ProfileID(userID.rawValue)
        let others = participantIDs.filter { $0 != viewerID }
        guard others.count == 1, let recipientID = others.first else {
            throw AppError.unknown(message: "Direct messages require exactly one other participant")
        }
        let recipient = Profile(
            id: recipientID,
            userID: UserID(recipientID.rawValue),
            username: "user",
            displayName: "User",
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
        return try await createDirectConversation(viewerID: viewerID, recipient: recipient)
    }

    func findExistingDirectConversationID(
        viewerID: ProfileID,
        recipientID: ProfileID
    ) async throws -> ConversationID? {
        #if DEBUG
        ConversationCreationTelemetry.recordRequest()
        #endif
        let me = viewerID.rawValue
        let them = recipientID.rawValue
        guard let raw = try await findExistingDMConversationID(me: me, them: them) else {
            return nil
        }
        return ConversationID(raw)
    }

    func usersHaveActiveBlock(viewerID: ProfileID, otherID: ProfileID) async -> Bool {
        #if DEBUG
        ConversationCreationTelemetry.recordRequest()
        #endif
        return await usersHaveActiveBlock(me: viewerID.rawValue, them: otherID.rawValue)
    }

    func createDirectConversation(viewerID: ProfileID, recipient: Profile) async throws -> Conversation {
        guard await session.currentUserID != nil else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let me = viewerID.rawValue
        let other = recipient.id.rawValue

        if let existingID = try await findExistingDMConversationID(me: me, them: other) {
            return ConversationCreationSupport.buildDirectConversation(
                id: ConversationID(existingID),
                viewerID: viewerID,
                recipient: recipient
            )
        }

        if await usersHaveActiveBlock(me: me, them: other) {
            throw AppError.unknown(
                message: "Direct messaging is unavailable while a user block is active."
            )
        }

        let conversationID = UUID().uuidString.lowercased()
        #if DEBUG
        ConversationCreationTelemetry.recordRequest()
        #endif
        try await supabase.database.insert(
            ConversationShell(id: conversationID, is_group: false),
            into: "conversations"
        )
        #if DEBUG
        ConversationCreationTelemetry.recordRequest()
        #endif
        try await supabase.database.insert(
            [
                ParticipantInsert(conversation_id: conversationID, user_id: me),
                ParticipantInsert(conversation_id: conversationID, user_id: other),
            ],
            into: "conversation_participants"
        )

        return ConversationCreationSupport.buildDirectConversation(
            id: ConversationID(conversationID),
            viewerID: viewerID,
            recipient: recipient
        )
    }

    func createGroupConversation(
        viewerID: ProfileID,
        recipients: [Profile],
        name: String?
    ) async throws -> Conversation {
        guard await session.currentUserID != nil else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let me = viewerID.rawValue
        let uniqueRecipients = recipients.filter { $0.id != viewerID }
        guard uniqueRecipients.count >= 2 else {
            throw AppError.unknown(message: "Group chats require at least two other participants")
        }

        let conversationID = UUID().uuidString.lowercased()
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (trimmedName?.isEmpty == false)
            ? trimmedName!
            : ConversationCreationSupport.fallbackGroupTitle(recipients: uniqueRecipients)

        #if DEBUG
        ConversationCreationTelemetry.recordRequest()
        #endif
        try await supabase.database.insert(
            GroupConversationShell(id: conversationID, is_group: true, name: resolvedName),
            into: "conversations"
        )

        var rows = uniqueRecipients.map {
            ParticipantInsert(conversation_id: conversationID, user_id: $0.id.rawValue)
        }
        rows.append(ParticipantInsert(conversation_id: conversationID, user_id: me))

        #if DEBUG
        ConversationCreationTelemetry.recordRequest()
        #endif
        do {
            try await supabase.database.insert(rows, into: "conversation_participants")
        } catch {
            throw AppError.unknown(message: "Could not add all group members. Please try again.")
        }

        return ConversationCreationSupport.buildGroupConversation(
            id: ConversationID(conversationID),
            viewerID: viewerID,
            recipients: uniqueRecipients,
            name: resolvedName
        )
    }

    func deleteConversation(id: ConversationID) async throws {
        // Exact web `handleDeleteConversation`:
        // delete from conversation_participants where conversation_id + user_id.
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        AppLog.networking.info(
            """
            conversations.delete begin \
            id=\(SafeInboxLog.hash(id.rawValue), privacy: .public)
            """
        )
        do {
            try await supabase.database.delete(
                from: "conversation_participants",
                query: [
                    SupabaseQuery.eq("conversation_id", id.rawValue),
                    SupabaseQuery.eq("user_id", userID.rawValue),
                ]
            )
            AppLog.networking.info(
                """
                conversations.delete ok \
                id=\(SafeInboxLog.hash(id.rawValue), privacy: .public) \
                status=204
                """
            )
        } catch {
            AppLog.networking.error(
                """
                conversations.delete failed \
                convo=\(SafeInboxLog.hash(id.rawValue), privacy: .public) \
                error=\(String(describing: error), privacy: .public)
                """
            )
            throw error
        }
    }

    func deleteMessageForEveryone(_ messageID: MessageID, in conversationID: ConversationID) async throws {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let body = DMDeleteForEveryoneBody(deleted_for_everyone: true)
        AppLog.networking.info(
            """
            messages.delete begin \
            message=\(SafeInboxLog.hash(messageID.rawValue), privacy: .public) \
            convo=\(SafeInboxLog.hash(conversationID.rawValue), privacy: .public)
            """
        )
        do {
            try await supabase.database.update(
                body,
                table: "messages",
                query: [
                    SupabaseQuery.eq("id", messageID.rawValue),
                    SupabaseQuery.eq("conversation_id", conversationID.rawValue),
                    SupabaseQuery.eq("sender_id", userID.rawValue),
                ]
            )
            AppLog.networking.info(
                """
                messages.delete ok \
                message=\(SafeInboxLog.hash(messageID.rawValue), privacy: .public) \
                status=204
                """
            )
        } catch {
            AppLog.networking.error(
                """
                messages.delete failed \
                message=\(SafeInboxLog.hash(messageID.rawValue), privacy: .public) \
                error=\(String(describing: error), privacy: .public)
                """
            )
            throw error
        }
    }

    func setConversationNotificationsEnabled(
        conversationID: ConversationID,
        enabled: Bool
    ) async throws {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let payload = ConversationMemberPreferencesUpsertBody(
            user_id: userID.rawValue,
            conversation_id: conversationID.rawValue,
            notifications_enabled: enabled
        )
        _ = try await supabase.database.upsert(
            payload,
            into: "conversation_member_preferences",
            onConflict: "user_id,conversation_id",
            returning: MessageDTO.MutedPreferenceRow.self,
            select: "conversation_id"
        )
    }

    func fetchDmBlockStatus(conversationID: ConversationID) async throws -> DmBlockStatus {
        try await fetchBlockStatus(
            rpcName: "get_dm_block_status",
            parameters: MessageRPCParams.ConversationID(p_conversation_id: conversationID.rawValue)
        )
    }

    func fetchUserBlockStatus(otherID: ProfileID) async throws -> DmBlockStatus {
        try await fetchBlockStatus(
            rpcName: "get_user_block_status",
            parameters: MessageRPCParams.OtherUserID(p_other_user_id: otherID.rawValue)
        )
    }

    func setDmUserBlock(conversationID: ConversationID, blocked: Bool) async throws -> DmBlockStatus {
        try await mutateBlock(
            rpcName: "set_dm_user_block",
            parameters: MessageRPCParams.SetDmBlock(
                p_conversation_id: conversationID.rawValue,
                p_blocked: blocked
            )
        )
    }

    func setUserBlock(otherID: ProfileID, blocked: Bool) async throws -> DmBlockStatus {
        try await mutateBlock(
            rpcName: "set_user_block",
            parameters: MessageRPCParams.SetUserBlock(
                p_blocked_id: otherID.rawValue,
                p_blocked: blocked
            )
        )
    }

    func fetchBlockedAccounts() async throws -> [BlockedAccount] {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let rows: [MessageDTO.UserBlockRow] = try await supabase.database.select(
            MessageDTO.UserBlockRow.self,
            from: "user_blocks",
            query: [
                SupabaseQuery.select(
                    "blocked_id,created_at,profiles:profiles!user_blocks_blocked_id_fkey(id,username,name,avatar_url)"
                ),
                SupabaseQuery.eq("blocker_id", userID.rawValue),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]
        )
        return rows.compactMap { row in
            guard let blockedID = row.blocked_id?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !blockedID.isEmpty
            else { return nil }
            let embedded = row.profiles
            let profile = Profile(
                id: ProfileID(blockedID),
                userID: UserID(blockedID),
                username: embedded?.username ?? "user",
                displayName: embedded?.name?.nilIfEmpty ?? embedded?.username ?? "User",
                bio: nil,
                avatar: embedded?.avatar_url.flatMap { url in
                    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : MediaReference(id: trimmed, kind: .image, altText: nil)
                },
                traderType: nil,
                tradingStyle: nil,
                primaryMarket: nil,
                startedTradingAt: nil,
                isPrivate: false,
                isCreator: false,
                createdAt: ISO8601.date(from: row.created_at ?? "") ?? .distantPast
            )
            return BlockedAccount(
                profile: profile,
                blockedAt: ISO8601.date(from: row.created_at ?? "")
            )
        }
    }

    func fetchMutedDirectMessagePeers() async throws -> [MutedDirectMessagePeer] {
        let data = try await supabase.database.rpcData(
            functionName: "list_muted_dm_peers",
            parametersJSON: Data("{}".utf8)
        )
        let rows = try JSONDecoder().decode([MessageDTO.MutedPeerRow].self, from: data)
        return rows.compactMap { row in
            guard let peerRaw = row.peer_id?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !peerRaw.isEmpty,
                  let conversationRaw = row.conversation_id?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !conversationRaw.isEmpty
            else { return nil }
            let profile = Profile(
                id: ProfileID(peerRaw),
                userID: UserID(peerRaw),
                username: row.username ?? "user",
                displayName: row.name?.nilIfEmpty ?? row.username ?? "User",
                bio: nil,
                avatar: row.avatar_url.flatMap { url in
                    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : MediaReference(id: trimmed, kind: .image, altText: nil)
                },
                traderType: nil,
                tradingStyle: nil,
                primaryMarket: nil,
                startedTradingAt: nil,
                isPrivate: false,
                isCreator: false,
                createdAt: .distantPast
            )
            return MutedDirectMessagePeer(
                profile: profile,
                conversationID: ConversationID(conversationRaw)
            )
        }
    }

    private func fetchBlockStatus<P: Encodable>(
        rpcName: String,
        parameters: P
    ) async throws -> DmBlockStatus {
        let data = try await supabase.database.rpcData(
            functionName: rpcName,
            parametersJSON: try JSONEncoder().encode(parameters)
        )
        guard let status = try decodeBlockStatus(from: data) else {
            throw AppError.unknown(message: "Could not determine block status.")
        }
        return status
    }

    private func mutateBlock<P: Encodable>(rpcName: String, parameters: P) async throws -> DmBlockStatus {
        let data = try await supabase.database.rpcData(
            functionName: rpcName,
            parametersJSON: try JSONEncoder().encode(parameters)
        )
        guard let status = try decodeBlockStatus(from: data) else {
            throw AppError.unknown(message: "Could not update block status.")
        }
        return status
    }

    private func decodeBlockStatus(from data: Data) throws -> DmBlockStatus? {
        let row: MessageDTO.BlockStatusRow
        if let single = try? JSONDecoder().decode(MessageDTO.BlockStatusRow.self, from: data) {
            row = single
        } else if let rows = try? JSONDecoder().decode([MessageDTO.BlockStatusRow].self, from: data),
                  let first = rows.first {
            row = first
        } else {
            return nil
        }
        guard let otherRaw = row.other_user_id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !otherRaw.isEmpty
        else { return nil }
        return DmBlockStatus(
            otherUserID: ProfileID(otherRaw),
            blockedByMe: row.blocked_by_me == true,
            blockedByOther: row.blocked_by_other == true
        )
    }

    // MARK: - Web pipeline helpers

    private func fetchHiddenBlockedConversationIDs() async -> Set<String> {
        do {
            let data = try await supabase.database.rpcData(
                functionName: "get_hidden_blocked_dm_conversation_ids",
                parametersJSON: Data("{}".utf8)
            )
            let rows = try JSONDecoder().decode([MessageDTO.HiddenBlockedRow].self, from: data)
            return Set(rows.compactMap(\.conversation_id).filter { !$0.isEmpty })
        } catch {
            return []
        }
    }

    private func fetchUnreadCounts(conversationIDs: [String]) async -> [String: Int] {
        guard !conversationIDs.isEmpty else { return [:] }
        do {
            let data = try await supabase.database.rpcData(
                functionName: "get_conversation_unread_counts",
                parametersJSON: try JSONEncoder().encode(
                    MessageRPCParams.ConversationIDs(p_conversation_ids: conversationIDs)
                )
            )
            let rows = try JSONDecoder().decode([MessageDTO.UnreadCountRow].self, from: data)
            var map: [String: Int] = [:]
            for row in rows {
                guard let id = row.conversation_id else { continue }
                map[id] = row.unread_count ?? 0
            }
            return map
        } catch {
            // Web fail-closed: empty unread map.
            return [:]
        }
    }

    private func fetchMutedConversationIDs(userID: String, conversationIDs: [String]) async -> Set<String> {
        guard !userID.isEmpty, !conversationIDs.isEmpty else { return [] }
        do {
            let rows: [MessageDTO.MutedPreferenceRow] = try await supabase.database.select(
                MessageDTO.MutedPreferenceRow.self,
                from: "conversation_member_preferences",
                query: [
                    SupabaseQuery.select("conversation_id"),
                    SupabaseQuery.eq("user_id", userID),
                    SupabaseQuery.eq("notifications_enabled", "false"),
                    SupabaseQuery.isIn("conversation_id", conversationIDs),
                ]
            )
            return Set(rows.compactMap(\.conversation_id).filter { !$0.isEmpty })
        } catch {
            return []
        }
    }

    private func findExistingDMConversationID(me: String, them: String) async throws -> String? {
        let mine: [MessageDTO.MembershipRow] = try await supabase.database.select(
            MessageDTO.MembershipRow.self,
            from: "conversation_participants",
            query: [
                SupabaseQuery.select("conversation_id"),
                SupabaseQuery.eq("user_id", me),
            ]
        )
        let ids = Array(Set(mine.compactMap(\.conversation_id).filter { !$0.isEmpty }))
        guard !ids.isEmpty else { return nil }

        var matches: [String] = []
        for chunk in ids.chunked(into: 80) {
            let meta: [MessageDTO.Conversation] = try await supabase.database.select(
                MessageDTO.Conversation.self,
                from: "conversations",
                query: [
                    SupabaseQuery.select("id,is_group"),
                    SupabaseQuery.isIn("id", chunk),
                ]
            )
            let dmIDs = meta.compactMap { dto -> String? in
                guard let id = dto.id, dto.is_group != true else { return nil }
                return id
            }
            guard !dmIDs.isEmpty else { continue }

            let parts: [MessageDTO.MembershipRow] = try await supabase.database.select(
                MessageDTO.MembershipRow.self,
                from: "conversation_participants",
                query: [
                    SupabaseQuery.select("conversation_id,user_id"),
                    SupabaseQuery.isIn("conversation_id", dmIDs),
                ]
            )
            var byConvo: [String: Set<String>] = [:]
            for row in parts {
                guard let cid = row.conversation_id, let uid = row.user_id else { continue }
                byConvo[cid, default: []].insert(uid)
            }
            for (cid, users) in byConvo {
                if users.count == 2, users.contains(me), users.contains(them) {
                    matches.append(cid)
                }
            }
        }
        return matches.sorted().first
    }

    private func usersHaveActiveBlock(me: String, them: String) async -> Bool {
        do {
            let data = try await supabase.database.rpcData(
                functionName: "users_have_active_block",
                parametersJSON: try JSONEncoder().encode(
                    MessageRPCParams.UserPair(p_user_a: me, p_user_b: them)
                )
            )
            if let flag = try? JSONDecoder().decode(Bool.self, from: data) {
                return flag
            }
            return false
        } catch {
            return false
        }
    }

    private func mapConversation(
        _ dto: MessageDTO.Conversation,
        viewerID: String,
        unreadCount: Int,
        isMuted: Bool
    ) -> Conversation? {
        guard let id = dto.id else { return nil }
        let isGroup = dto.is_group == true
        let participants = dto.participants ?? []
        let participantIDs = participants.compactMap(\.user_id).map { ProfileID($0) }
        let other = participants.first { $0.user_id != viewerID }
        let profile = other?.profiles
        let peerUsername = isGroup ? nil : (profile?.username ?? "user")
        let title: String?
        if isGroup {
            title = dto.name?.nilIfEmpty ?? "Group Chat"
        } else {
            title = profile?.name?.nilIfEmpty ?? peerUsername
        }
        let avatarURL = isGroup ? dto.avatar_url : profile?.avatar_url
        let lastAt = ISO8601.date(from: dto.last_message_at)
        return Conversation(
            id: ConversationID(id),
            participantProfileIDs: participantIDs,
            title: title,
            peerUsername: peerUsername,
            avatar: avatarURL.flatMap { $0.nilIfEmpty }.map {
                MediaReference(id: $0, kind: .image, altText: nil)
            },
            isGroup: isGroup,
            isPinned: dto.is_pinned == true,
            lastMessagePreview: ConversationInboxActivity.preview(fromStoredContent: dto.last_message),
            lastMessageAt: lastAt,
            unreadCount: unreadCount,
            isMuted: isMuted,
            updatedAt: lastAt ?? .distantPast
        )
    }

    private func extractEmbeddedProfiles(from dto: MessageDTO.Conversation) -> [Profile] {
        (dto.participants ?? []).compactMap { participant -> Profile? in
            guard let uid = participant.user_id?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !uid.isEmpty
            else { return nil }
            let embed = participant.profiles
            let username = embed?.username?.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = embed?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let avatar = embed?.avatar_url?.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = ProfileID(embed?.id?.nilIfEmpty ?? uid)
            return Profile(
                id: id,
                userID: UserID(id.rawValue),
                username: (username?.isEmpty == false) ? username! : "user",
                displayName: (display?.isEmpty == false) ? display! : (username ?? "user"),
                bio: nil,
                avatar: {
                    guard let avatar, !avatar.isEmpty else { return nil }
                    return MediaReference(id: avatar, kind: .image, altText: nil)
                }(),
                traderType: nil,
                tradingStyle: nil,
                primaryMarket: nil,
                startedTradingAt: nil,
                isPrivate: false,
                isCreator: false,
                createdAt: Date()
            )
        }
    }

    /// Web `sortConversationsDesc` — pinned first, then `last_message_at` desc.
    private func sortConversations(_ items: [Conversation]) -> [Conversation] {
        items.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            let ld = lhs.lastMessageAt ?? .distantPast
            let rd = rhs.lastMessageAt ?? .distantPast
            return ld > rd
        }
    }

    /// Web `handleSendTrade` payload — does not invent a new message type.
    private func sendTradeShare(_ message: Message, tradeID: TradeID) async throws -> Message {
        let body = MessageInsertBodies.TradeShare(
            conversation_id: message.conversationID.rawValue,
            sender_id: message.senderProfileID.rawValue,
            type: "trade",
            trade_id: tradeID.rawValue,
            content: nil,
            parent_message_id: message.replyToMessageID?.rawValue
        )
        let inserted: DMInsertRow = try await supabase.database.insert(
            body,
            into: "messages",
            query: [SupabaseQuery.select("id,created_at")],
            returning: DMInsertRow.self
        )
        guard let id = inserted.id, !id.isEmpty else {
            throw AppError.unknown(message: "Trade share insert returned no id")
        }
        // Web trade share also calls `createDirectMessagePush` after insert.
        scheduleDirectMessagePush(messageID: id)
        return Message(
            id: MessageID(id),
            conversationID: message.conversationID,
            senderProfileID: message.senderProfileID,
            kind: .tradeShare,
            body: nil,
            attachments: [
                MessageAttachment(
                    id: tradeID.rawValue,
                    media: MediaReference(id: tradeID.rawValue, kind: .file, altText: "Shared trade"),
                    tradeID: tradeID
                ),
            ],
            replyToMessageID: message.replyToMessageID,
            createdAt: ISO8601.date(from: inserted.created_at) ?? message.createdAt,
            isReadByViewer: true
        )
    }

    private func sendStoryShare(_ message: Message, content: String) async throws -> Message {
        let body = MessageInsertBodies.StoryShare(
            conversation_id: message.conversationID.rawValue,
            sender_id: message.senderProfileID.rawValue,
            type: StoryShareMessageSupport.messageType,
            content: content,
            parent_message_id: message.replyToMessageID?.rawValue
        )
        let inserted: DMInsertRow = try await supabase.database.insert(
            body,
            into: "messages",
            query: [SupabaseQuery.select("id,created_at")],
            returning: DMInsertRow.self
        )
        guard let id = inserted.id, !id.isEmpty else {
            throw AppError.unknown(message: "Story share insert returned no id")
        }
        scheduleDirectMessagePush(messageID: id)
        return Message(
            id: MessageID(id),
            conversationID: message.conversationID,
            senderProfileID: message.senderProfileID,
            kind: .storyShare,
            body: content,
            attachments: [],
            replyToMessageID: message.replyToMessageID,
            createdAt: ISO8601.date(from: inserted.created_at) ?? message.createdAt,
            isReadByViewer: true
        )
    }

    private func sendVoiceMessage(_ message: Message, audioURL: String) async throws -> Message {
        let durationMs = message.attachments.first?.durationSeconds.map {
            Int(($0 * 1_000).rounded())
        }
        let body = DMVoiceSendBody(
            conversation_id: message.conversationID.rawValue,
            sender_id: message.senderProfileID.rawValue,
            type: "voice",
            content: "",
            audio_url: audioURL,
            audio_duration_ms: durationMs,
            parent_message_id: message.replyToMessageID?.rawValue
        )
        let inserted: DMInsertRow = try await supabase.database.insert(
            body,
            into: "messages",
            query: [SupabaseQuery.select("id,created_at")],
            returning: DMInsertRow.self
        )
        guard let id = inserted.id, !id.isEmpty else {
            throw AppError.unknown(message: "Voice message insert returned no id")
        }
        scheduleDirectMessagePush(messageID: id)
        return Message(
            id: MessageID(id),
            conversationID: message.conversationID,
            senderProfileID: message.senderProfileID,
            kind: .voice,
            body: nil,
            attachments: message.attachments,
            replyToMessageID: message.replyToMessageID,
            createdAt: ISO8601.date(from: inserted.created_at) ?? message.createdAt,
            isReadByViewer: true
        )
    }

    /// Web `void createDirectMessagePush(...)` — start the BFF pipeline without blocking send.
    private func scheduleDirectMessagePush(messageID: String) {
        let transport = supabase.transport
        Task {
            await DirectMessagePushClient(transport: transport)
                .notifyAfterSuccessfulInsert(messageID: messageID)
        }
    }
}

private nonisolated struct ConversationShell: Encodable, Sendable {
    var id: String
    var is_group: Bool
}

private nonisolated struct GroupConversationShell: Encodable, Sendable {
    var id: String
    var is_group: Bool
    var name: String
}

private nonisolated struct ParticipantInsert: Encodable, Sendable {
    var conversation_id: String
    var user_id: String
}

private nonisolated enum MessageRPCParams {
    struct ConversationID: Encodable, Sendable {
        var p_conversation_id: String
    }

    struct ConversationIDs: Encodable, Sendable {
        var p_conversation_ids: [String]
    }

    struct UserPair: Encodable, Sendable {
        var p_user_a: String
        var p_user_b: String
    }

    struct OtherUserID: Encodable, Sendable {
        var p_other_user_id: String
    }

    struct SetDmBlock: Encodable, Sendable {
        var p_conversation_id: String
        var p_blocked: Bool
    }

    struct SetUserBlock: Encodable, Sendable {
        var p_blocked_id: String
        var p_blocked: Bool
    }
}

private nonisolated enum MessageInsertBodies {
    struct TradeShare: Encodable, Sendable {
        var conversation_id: String
        var sender_id: String
        var type: String
        var trade_id: String
        var content: String?
        var parent_message_id: String?

        private enum CodingKeys: String, CodingKey {
            case conversation_id, sender_id, type, trade_id, content, channel, parent_message_id
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(conversation_id, forKey: .conversation_id)
            try container.encode(sender_id, forKey: .sender_id)
            try container.encode(type, forKey: .type)
            try container.encode(trade_id, forKey: .trade_id)
            try container.encodeNil(forKey: .content)
            try container.encodeNil(forKey: .channel)
            if let parent_message_id {
                try container.encode(parent_message_id, forKey: .parent_message_id)
            }
        }
    }

    struct StoryShare: Encodable, Sendable {
        var conversation_id: String
        var sender_id: String
        var type: String
        var content: String
        var parent_message_id: String?

        private enum CodingKeys: String, CodingKey {
            case conversation_id, sender_id, type, content, channel, parent_message_id
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(conversation_id, forKey: .conversation_id)
            try container.encode(sender_id, forKey: .sender_id)
            try container.encode(type, forKey: .type)
            try container.encode(content, forKey: .content)
            try container.encodeNil(forKey: .channel)
            if let parent_message_id {
                try container.encode(parent_message_id, forKey: .parent_message_id)
            }
        }
    }
}

private nonisolated struct DMSendBody: Encodable, Sendable {
    var conversation_id: String
    var sender_id: String
    var content: String
    var image_url: String?
    var parent_message_id: String?

    private enum CodingKeys: String, CodingKey {
        case conversation_id
        case sender_id
        case content
        case image_url
        case channel
        case parent_message_id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conversation_id, forKey: .conversation_id)
        try container.encode(sender_id, forKey: .sender_id)
        try container.encode(content, forKey: .content)
        try container.encode(image_url, forKey: .image_url)
        try container.encodeNil(forKey: .channel)
        if let parent_message_id {
            try container.encode(parent_message_id, forKey: .parent_message_id)
        }
    }
}

private nonisolated struct DMVoiceSendBody: Encodable, Sendable {
    var conversation_id: String
    var sender_id: String
    var type: String
    var content: String
    var audio_url: String
    var audio_duration_ms: Int?
    var parent_message_id: String?

    private enum CodingKeys: String, CodingKey {
        case conversation_id
        case sender_id
        case type
        case content
        case audio_url
        case audio_duration_ms
        case channel
        case parent_message_id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conversation_id, forKey: .conversation_id)
        try container.encode(sender_id, forKey: .sender_id)
        try container.encode(type, forKey: .type)
        try container.encode(content, forKey: .content)
        try container.encode(audio_url, forKey: .audio_url)
        if let audio_duration_ms {
            try container.encode(audio_duration_ms, forKey: .audio_duration_ms)
        }
        try container.encodeNil(forKey: .channel)
        if let parent_message_id {
            try container.encode(parent_message_id, forKey: .parent_message_id)
        }
    }
}

private nonisolated struct DMDeleteForEveryoneBody: Encodable, Sendable {
    var deleted_for_everyone: Bool
}

private nonisolated struct ConversationMemberPreferencesUpsertBody: Encodable, Sendable {
    var user_id: String
    var conversation_id: String
    var notifications_enabled: Bool
}

private nonisolated struct DMInsertRow: Decodable, Sendable {
    var id: String?
    var created_at: String?
}

private nonisolated extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

