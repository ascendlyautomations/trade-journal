import Foundation

/// Published Demo snapshot. Journal totals stay derived from ``trades``; this document stores source rows only.
nonisolated struct DemoSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var version: Int
    var publishedAt: Date
    var viewer: Profile
    var peers: [Profile]
    var host: Profile
    var accounts: [TradingAccount]
    var trades: [Trade]
    var checkIns: [TraderDailyCheckIn]
    var payouts: [AccountPayoutEntry]
    var posts: [Post]
    var clips: [Reel]
    var stories: [Story]
    var achievements: [Achievement]
    var activity: [ActivityNotification]
    var conversations: [Conversation]
    var messages: [Message]
    var room: TradeRoom
    var channels: [RoomChannel]
    var memberships: [RoomMembership]
    var roomMessages: [RoomMessage]
    var vaultFolders: [VaultFolder]
    var vaultItems: [VaultItem]

    /// Point-in-time copy of the bundled Phase 1 generators.
    static func captureBundled(now: Date = Date(), version: Int = 1) -> DemoSnapshot {
        DemoSnapshotStore.shared.withBundledSource {
            let viewer = DemoCanonicalDataset.profile(now: now)
            let room = DemoExploreTradeRoom.room(now: now)
            let vault = DemoVaultRepository.bundledCatalog(now: now)
            return DemoSnapshot(
                schemaVersion: currentSchemaVersion,
                version: version,
                publishedAt: now,
                viewer: viewer,
                peers: DemoGraph.profiles(),
                host: DemoExploreTradeRoom.hostProfile(),
                accounts: DemoCanonicalDataset.accounts(),
                trades: DemoCanonicalDataset.trades(now: now),
                checkIns: DemoCanonicalDataset.checkIns(now: now),
                payouts: DemoCanonicalDataset.accounts().flatMap {
                    DemoCanonicalDataset.payoutEntries(for: $0.id)
                },
                posts: DemoGraph.posts(),
                clips: DemoGraph.clips(),
                stories: DemoGraph.stories(),
                achievements: DemoGraph.achievements(),
                activity: DemoGraph.notifications(now: now),
                conversations: DemoGraph.conversations(viewerID: viewer.id),
                messages: DemoGraph.messages(
                    conversationID: DemoGraph.sarahConversationID,
                    viewerID: viewer.id
                ),
                room: room,
                channels: DemoExploreTradeRoom.channels(),
                memberships: memberships(room: room, viewerID: viewer.id, now: now),
                roomMessages: DemoExploreTradeRoom.messages(viewerID: viewer.id, now: now),
                vaultFolders: vault.folders,
                vaultItems: vault.items
            )
        }
    }

    func validate() -> [String] {
        var problems: [String] = []
        if schemaVersion != Self.currentSchemaVersion {
            problems.append("schemaVersion")
        }
        if version < 1 {
            problems.append("version")
        }
        if viewer.id != DemoExperienceSupport.profileID {
            problems.append("viewer")
        }
        if accounts.isEmpty || trades.isEmpty {
            problems.append("journal")
        }

        let accountIDs = Set(accounts.map(\.id))
        let tradeIDs = Set(trades.map(\.id))
        var profileIDs = Set(peers.map(\.id))
        profileIDs.insert(viewer.id)
        profileIDs.insert(host.id)

        if trades.contains(where: { $0.accountID.map(accountIDs.contains) != true }) {
            problems.append("trade.account")
        }
        if trades.contains(where: { !profileIDs.contains($0.ownerProfileID) }) {
            problems.append("trade.owner")
        }
        if posts.contains(where: { $0.linkedTradeID.map(tradeIDs.contains) == false }) {
            problems.append("post.trade")
        }
        if clips.contains(where: { $0.linkedTradeID.map(tradeIDs.contains) == false }) {
            problems.append("clip.trade")
        }
        if payouts.contains(where: { !accountIDs.contains($0.accountID) }) {
            problems.append("payout.account")
        }
        if activity.contains(where: { $0.tradeID.map(tradeIDs.contains) == false }) {
            problems.append("activity.trade")
        }
        if activity.contains(where: { $0.actorProfileID.map(profileIDs.contains) == false }) {
            problems.append("activity.actor")
        }
        if activity.contains(where: { $0.kind == .tradingReport && $0.reportID?.rawValue != "monthly_last" }) {
            problems.append("activity.report")
        }
        if messages.contains(where: { message in
            guard let shared = message.sharedContent else { return false }
            if case .trade(let tradeID) = shared { return !tradeIDs.contains(tradeID) }
            return false
        }) {
            problems.append("message.trade")
        }
        if messages.contains(where: { !profileIDs.contains($0.senderProfileID) }) {
            problems.append("message.sender")
        }
        if roomMessages.contains(where: { $0.attachedTradeID.map(tradeIDs.contains) == false }) {
            problems.append("roomMessage.trade")
        }
        if roomMessages.contains(where: { !profileIDs.contains($0.senderProfileID) }) {
            problems.append("roomMessage.sender")
        }
        if memberships.contains(where: { !profileIDs.contains($0.profileID) || $0.roomID != room.id }) {
            problems.append("membership")
        }
        if vaultItems.contains(where: { item in
            guard item.ref.contentType == .trade else { return false }
            return !tradeIDs.contains(TradeID(item.ref.contentID))
        }) {
            problems.append("vault.trade")
        }
        let folderIDs = Set(vaultFolders.map(\.id))
        if vaultItems.contains(where: { item in
            item.folderIDs.contains { !folderIDs.contains($0) }
        }) {
            problems.append("vault.folder")
        }
        return problems
    }

    private static func memberships(room: TradeRoom, viewerID: ProfileID, now: Date) -> [RoomMembership] {
        [
            RoomMembership(
                roomID: room.id,
                profileID: room.ownerProfileID,
                role: .owner,
                joinedAt: room.createdAt,
                notificationsEnabled: true
            ),
            RoomMembership(
                roomID: room.id,
                profileID: DemoGraph.sarahID,
                role: .admin,
                joinedAt: room.createdAt.addingTimeInterval(86_400),
                notificationsEnabled: true
            ),
            RoomMembership(
                roomID: room.id,
                profileID: DemoGraph.alexID,
                role: .member,
                joinedAt: room.createdAt.addingTimeInterval(172_800),
                notificationsEnabled: true
            ),
            RoomMembership(
                roomID: room.id,
                profileID: DemoGraph.mikeID,
                role: .member,
                joinedAt: room.createdAt.addingTimeInterval(200_000),
                notificationsEnabled: true
            ),
            RoomMembership(
                roomID: room.id,
                profileID: viewerID,
                role: .member,
                joinedAt: now.addingTimeInterval(-604_800),
                notificationsEnabled: true
            ),
        ]
    }
}

nonisolated enum DemoSnapshotCoding {
    static func encode(_ snapshot: DemoSnapshot) throws -> Data {
        try encoder().encode(snapshot)
    }

    static func decode(_ data: Data) throws -> DemoSnapshot {
        try decoder().decode(DemoSnapshot.self, from: normalize(data))
    }

    /// Admin records can omit bools the native models require, or store an empty id.
    /// Fill those before decode so one incomplete row cannot reject the whole snapshot.
    static func normalize(_ data: Data) -> Data {
        guard var root = jsonObject(data) else { return data }
        root["activity"] = mapObjects(root["activity"]) { item in
            if item["isReply"] == nil { item["isReply"] = false }
            if item["isMention"] == nil { item["isMention"] = false }
            if item["isRead"] == nil { item["isRead"] = false }
            dropEmptyStrings(
                &item,
                keys: ["tradeID", "postID", "profilePostID", "achievementPostID", "reelID", "commentID", "conversationID", "roomID", "roomMessageID", "reportID", "actorProfileID"]
            )
        }
        root["conversations"] = mapObjects(root["conversations"]) { item in
            if item["isGroup"] == nil { item["isGroup"] = false }
            if item["isPinned"] == nil { item["isPinned"] = false }
            if item["unreadCount"] == nil { item["unreadCount"] = 0 }
            if item["isMuted"] == nil { item["isMuted"] = false }
            if item["participantProfileIDs"] == nil { item["participantProfileIDs"] = [Any]() }
        }
        root["messages"] = mapObjects(root["messages"]) { item in
            if item["attachments"] == nil { item["attachments"] = [Any]() }
            if item["roomReactions"] == nil { item["roomReactions"] = [Any]() }
            if item["isReadByViewer"] == nil { item["isReadByViewer"] = false }
        }
        guard JSONSerialization.isValidJSONObject(root),
              let encoded = try? JSONSerialization.data(withJSONObject: root)
        else { return data }
        return encoded
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func mapObjects(_ value: Any?, _ body: (inout [String: Any]) -> Void) -> Any? {
        guard let items = value as? [Any] else { return value }
        return items.map { item in
            guard var object = item as? [String: Any] else { return item }
            body(&object)
            return object
        }
    }

    private static func dropEmptyStrings(_ object: inout [String: Any], keys: [String]) {
        for key in keys {
            if let text = object[key] as? String, text.isEmpty {
                object.removeValue(forKey: key)
            }
        }
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.fractional.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = fractional.date(from: value) ?? plain.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date"
            )
        }
        return decoder
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

nonisolated enum DemoSnapshotRefreshResult: Equatable, Sendable {
    case applied(version: Int)
    case unchanged(version: Int)
    case rejected
    case unavailable
}
