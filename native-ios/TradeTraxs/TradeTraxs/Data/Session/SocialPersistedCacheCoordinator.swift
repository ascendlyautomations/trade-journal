import Foundation

/// Central write-through for viewer-scoped social disk snapshots.
@MainActor
enum SocialPersistedCacheCoordinator {
    // MARK: - Inbox

    @discardableResult
    static func hydrateInbox(viewerID: ProfileID, inboxStore: MessagesInboxStore) -> Bool {
        guard let blob = SocialDiskCache.loadInbox(for: viewerID) else { return false }
        var roomPreviews: [RoomID: String] = [:]
        for (key, value) in blob.roomPreviews {
            roomPreviews[RoomID(key)] = value
        }
        var roomActivityAt: [RoomID: Date] = [:]
        for (key, value) in blob.roomActivityAt {
            roomActivityAt[RoomID(key)] = value
        }
        var roomUnread: [RoomID: Int] = [:]
        for (key, value) in blob.roomUnread {
            roomUnread[RoomID(key)] = value
        }
        var unreadOverrides: [ConversationID: Int] = [:]
        for (key, value) in blob.unreadOverrides {
            unreadOverrides[ConversationID(key)] = value
        }
        inboxStore.hydrateFromDisk(
            viewerID: viewerID,
            conversations: blob.conversations,
            rooms: blob.rooms,
            roomPreviews: roomPreviews,
            roomActivityAt: roomActivityAt,
            roomUnread: roomUnread,
            unreadOverrides: unreadOverrides,
            pinnedConversationIDs: Set(blob.pinnedConversationIDs.map { ConversationID($0) }),
            mutedConversationIDs: Set(blob.mutedConversationIDs.map { ConversationID($0) }),
            mutedRoomIDs: Set(blob.mutedRoomIDs.map { RoomID($0) }),
            savedAt: blob.savedAt
        )
        SocialCacheProbe.recordInboxDiskHit(conversations: blob.conversations.count, rooms: blob.rooms.count)
        return true
    }

    static func persistInbox(viewerID: ProfileID, from inboxStore: MessagesInboxStore) {
        let blob = SocialDiskCache.InboxBlob(
            viewerID: viewerID.rawValue,
            savedAt: Date(),
            conversations: inboxStore.conversations,
            rooms: inboxStore.rooms,
            roomPreviews: Dictionary(uniqueKeysWithValues: inboxStore.roomPreviews.map { ($0.key.rawValue, $0.value) }),
            roomActivityAt: Dictionary(uniqueKeysWithValues: inboxStore.roomActivityAt.map { ($0.key.rawValue, $0.value) }),
            roomUnread: Dictionary(uniqueKeysWithValues: inboxStore.roomUnread.map { ($0.key.rawValue, $0.value) }),
            unreadOverrides: Dictionary(uniqueKeysWithValues: inboxStore.unreadOverridesForPersistence.map { ($0.key.rawValue, $0.value) }),
            pinnedConversationIDs: inboxStore.pinnedConversationIDsForPersistence.map(\.rawValue),
            mutedConversationIDs: inboxStore.mutedConversationIDsForPersistence.map(\.rawValue),
            mutedRoomIDs: inboxStore.mutedRoomIDsForPersistence.map(\.rawValue)
        )
        SocialDiskCache.saveInbox(blob)
    }

    // MARK: - DM threads

    static func restoreDMThread(
        viewerID: ProfileID,
        conversationID: ConversationID
    ) -> ConversationThreadSessionStore.Snapshot? {
        guard let blob = SocialDiskCache.loadDMThread(viewerID: viewerID, conversationID: conversationID) else {
            return nil
        }
        let key = ConversationThreadSessionStore.cacheKey(viewerID: viewerID, conversationID: conversationID)
        let snapshot = ConversationThreadSessionStore.Snapshot(
            cacheKey: key,
            conversation: blob.conversation,
            messages: blob.messages,
            nextCursor: blob.nextCursor,
            hasMoreMessages: blob.hasMoreMessages,
            loadedAt: blob.savedAt,
            contentGeneration: blob.contentGeneration
        )
        SocialCacheProbe.recordDMThreadDiskHit()
        return snapshot
    }

    static func persistDMThread(
        viewerID: ProfileID,
        conversationID: ConversationID,
        snapshot: ConversationThreadSessionStore.Snapshot
    ) {
        let blob = SocialDiskCache.DMThreadBlob(
            viewerID: viewerID.rawValue,
            conversationID: conversationID.rawValue,
            savedAt: Date(),
            lastAccessedAt: Date(),
            conversation: snapshot.conversation,
            messages: snapshot.messages,
            nextCursor: snapshot.nextCursor,
            hasMoreMessages: snapshot.hasMoreMessages,
            contentGeneration: snapshot.contentGeneration
        )
        SocialDiskCache.saveDMThread(blob)
    }

    static func removeDMThread(viewerID: ProfileID, conversationID: ConversationID) {
        SocialDiskCache.removeDMThread(viewerID: viewerID, conversationID: conversationID)
    }

    // MARK: - Member rooms

    @discardableResult
    static func hydrateMemberRooms(
        viewerID: ProfileID,
        inboxStore: MessagesInboxStore,
        memberRoomsStore: SessionMemberRoomsStore
    ) -> Bool {
        guard let blob = SocialDiskCache.loadMemberRooms(for: viewerID) else { return false }
        var unread: [RoomID: Int] = [:]
        for (key, value) in blob.unread {
            unread[RoomID(key)] = value
        }
        var activityAt: [RoomID: Date] = [:]
        for (key, value) in blob.activityAt {
            activityAt[RoomID(key)] = value
        }
        memberRoomsStore.seed(
            rooms: blob.rooms,
            unread: unread,
            activityAt: activityAt,
            for: viewerID,
            savedAt: blob.savedAt
        )
        if inboxStore.rooms.isEmpty {
            inboxStore.replaceRooms(blob.rooms, activityAt: activityAt, unread: unread)
        }
        SocialCacheProbe.recordRoomListDiskHit(rooms: blob.rooms.count)
        return true
    }

    static func persistMemberRooms(viewerID: ProfileID, from store: SessionMemberRoomsStore) {
        guard let snapshot = store.snapshotForPersistence(viewerID: viewerID) else { return }
        let blob = SocialDiskCache.MemberRoomsBlob(
            viewerID: viewerID.rawValue,
            savedAt: Date(),
            rooms: snapshot.rooms,
            unread: Dictionary(uniqueKeysWithValues: snapshot.unread.map { ($0.key.rawValue, $0.value) }),
            activityAt: Dictionary(uniqueKeysWithValues: snapshot.activityAt.map { ($0.key.rawValue, $0.value) })
        )
        SocialDiskCache.saveMemberRooms(blob)
        persistInbox(viewerID: viewerID, from: MessagesInboxStore.shared)
    }

    // MARK: - Room thread snapshots

    static func restoreRoomSnapshot(viewerID: ProfileID, roomID: RoomID) -> SocialDiskCache.RoomSnapshotBlob? {
        guard let blob = SocialDiskCache.loadRoomSnapshot(viewerID: viewerID, roomID: roomID) else {
            return nil
        }
        SocialCacheProbe.recordRoomThreadDiskHit()
        return blob
    }

    static func persistRoomSnapshot(
        viewerID: ProfileID,
        roomID: RoomID,
        room: TradeRoom,
        membership: RoomMembership?,
        channels: [RoomChannel],
        selectedChannelID: RoomChannelID?,
        channelThreads: [RoomChannelID: SocialDiskCache.RoomChannelThreadBlob]
    ) {
        let blob = SocialDiskCache.RoomSnapshotBlob(
            viewerID: viewerID.rawValue,
            roomID: roomID.rawValue,
            savedAt: Date(),
            lastAccessedAt: Date(),
            room: room,
            membership: membership,
            channels: channels,
            selectedChannelID: selectedChannelID?.rawValue,
            channelThreads: Dictionary(uniqueKeysWithValues: channelThreads.map { ($0.key.rawValue, $0.value) })
        )
        SocialDiskCache.saveRoomSnapshot(blob)
    }

    static func invalidateRoomSnapshot(viewerID: ProfileID, roomID: RoomID) {
        SocialDiskCache.removeRoomSnapshot(viewerID: viewerID, roomID: roomID)
    }

    // MARK: - Activity

    @discardableResult
    static func hydrateActivity(viewerID: ProfileID, store: ActivityInboxStore) -> Bool {
        guard let blob = SocialDiskCache.loadActivity(for: viewerID) else { return false }
        store.hydrateFromDisk(
            viewerID: viewerID,
            items: blob.items,
            unreadCount: blob.unreadCount,
            pendingFollowRequestCount: blob.pendingFollowRequestCount,
            nextCursor: blob.nextCursor,
            savedAt: blob.savedAt
        )
        SocialCacheProbe.recordActivityDiskHit(items: blob.items.count)
        return true
    }

    static func persistActivity(viewerID: ProfileID, from store: ActivityInboxStore) {
        let blob = SocialDiskCache.ActivityBlob(
            viewerID: viewerID.rawValue,
            savedAt: Date(),
            items: store.items,
            unreadCount: store.unreadCount,
            pendingFollowRequestCount: store.pendingFollowRequestCount,
            nextCursor: store.nextCursor
        )
        SocialDiskCache.saveActivity(blob)
    }

    // MARK: - Session isolation

    static func clear(viewerID: ProfileID) {
        SocialDiskCache.clear(viewerID: viewerID)
    }

    static func clearAll() {
        SocialDiskCache.clearAll()
    }
}
