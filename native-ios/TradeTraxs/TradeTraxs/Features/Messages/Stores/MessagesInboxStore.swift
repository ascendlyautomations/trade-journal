import Foundation
import Observation

/// Session cache for Messages home — load once, mutate in place (swipe / new chat / leave).
///
/// Realtime product channels are registry-only today; when conversation events arrive,
/// call ``applyConversationUpdate(_:)`` / ``replaceConversations(_:)`` instead of forcing
/// a full inbox remount.
@Observable
@MainActor
final class MessagesInboxStore {
    static let shared = MessagesInboxStore()

    private(set) var conversations: [Conversation] = []
    private(set) var rooms: [TradeRoom] = []
    private(set) var roomPreviews: [RoomID: String] = [:]
    private(set) var roomUnread: [RoomID: Int] = [:]
    /// DM thread currently open — suppresses inbox unread bumps from home realtime.
    private(set) var activeConversationID: ConversationID?
    /// Room currently open in the conversation shell — suppresses inbox unread bumps.
    private(set) var activeRoomID: RoomID?
    private(set) var hasLoaded = false
    /// True after the first member-rooms hydration (Messages or Trade Rooms home).
    private(set) var hasLoadedRooms = false
    private(set) var lastLoadedAt: Date?

    /// Optimistic mute overrides until the next inbox bootstrap; server state via `conversation_member_preferences`.
    private var mutedConversationIDs: Set<ConversationID> = []
    private var pinnedConversationIDs: Set<ConversationID> = []
    private var mutedRoomIDs: Set<RoomID> = []
    private var typingConversationIDs: Set<ConversationID> = []
    private var onlineProfileIDs: Set<ProfileID> = []
    private var unreadOverrides: [ConversationID: Int] = [:]
    /// Optimistic room unread clears that must survive bootstrap until the server agrees.
    private var roomUnreadOverrides: [RoomID: Int] = [:]
    private var hiddenConversationIDs: Set<ConversationID> = []
    private var pendingDeleteConversationIDs: Set<ConversationID> = []

    /// Monotonic publish token — SwiftUI observes this for preview/order updates.
    private(set) var activityRevision: UInt64 = 0

#if DEBUG
    /// Non-sensitive store identity for wiring audits.
    let debugInstanceToken: String = String(UUID().uuidString.prefix(8))
#endif

    private init() {
#if DEBUG
        SafeInboxLog.storeCreated(instance: debugInstanceToken)
#endif
    }

    var debugInstance: String {
#if DEBUG
        debugInstanceToken
#else
        "release"
#endif
    }

    /// Web `sortConversationsDesc` order with hidden rows removed.
    var visibleConversations: [Conversation] {
        conversations.filter { !hiddenConversationIDs.contains($0.id) }
    }

    var hasPendingConversationDeletes: Bool {
        !pendingDeleteConversationIDs.isEmpty
    }

    /// Sum of effective DM unread counts — used by Messages inbox UI (not app-icon badge).
    var totalDirectMessageUnread: Int {
        visibleConversations.reduce(0) { partial, conversation in
            partial + unreadCount(for: conversation)
        }
    }

    func replaceConversations(_ items: [Conversation]) {
        let unhideIDs = Set(items.map(\.id)).subtracting(pendingDeleteConversationIDs)
        hiddenConversationIDs.subtract(unhideIDs)
        // Seed pin/mute from repository (web prefs / is_pinned) — local toggles may still override.
        pinnedConversationIDs = Set(items.filter(\.isPinned).map(\.id))
        mutedConversationIDs = Set(items.filter(\.isMuted).map(\.id))
        let previousOverrides = unreadOverrides
        var nextOverrides: [ConversationID: Int] = [:]
        let merged = items.map { item -> Conversation in
            var copy = item
            if let override = previousOverrides[item.id] {
                if item.unreadCount == override {
                    // Backend confirmed the local value — drop the override.
                } else {
                    // Keep optimistic / local unread (e.g. cleared to 0 before RPC finished).
                    copy.unreadCount = override
                    nextOverrides[item.id] = override
                }
            }
            return copy
        }
        // Preserve overrides for conversations not yet in the bootstrap payload
        // (cold-start push open before inbox rows arrive).
        for (id, override) in previousOverrides where items.contains(where: { $0.id == id }) == false {
            nextOverrides[id] = override
        }
        unreadOverrides = nextOverrides
        conversations = Self.sortConversationsDesc(merged, pinned: pinnedConversationIDs)
        DirectConversationPairIndex.shared.rebuild(from: conversations)
        hasLoaded = true
        lastLoadedAt = .now
        bumpActivityRevision()
    }

    /// Merge bootstrap rows without clobbering newer local send/realtime activity.
    func mergeConversationsFromBootstrap(_ incoming: [Conversation]) {
        let unhideIDs = Set(incoming.map(\.id)).subtracting(pendingDeleteConversationIDs)
        hiddenConversationIDs.subtract(unhideIDs)
        pinnedConversationIDs.formUnion(incoming.filter(\.isPinned).map(\.id))
        mutedConversationIDs.formUnion(incoming.filter(\.isMuted).map(\.id))

        let previousOverrides = unreadOverrides
        var byID: [ConversationID: Conversation] = Dictionary(
            uniqueKeysWithValues: conversations.map { ($0.id, $0) }
        )

        for item in incoming {
            if let existing = byID[item.id] {
                var merged = ConversationInboxActivity.mergeConversations(existing: existing, incoming: item)
                if let override = previousOverrides[item.id] {
                    if item.unreadCount == override {
                        unreadOverrides.removeValue(forKey: item.id)
                    } else {
                        merged.unreadCount = override
                        unreadOverrides[item.id] = override
                    }
                }
                byID[item.id] = merged
            } else {
                var copy = item
                if let override = previousOverrides[item.id] {
                    copy.unreadCount = override
                    unreadOverrides[item.id] = override
                }
                byID[item.id] = copy
            }
        }

        conversations = Self.sortConversationsDesc(Array(byID.values), pinned: pinnedConversationIDs)
        DirectConversationPairIndex.shared.rebuild(from: conversations)
        hasLoaded = true
        lastLoadedAt = .now
        bumpActivityRevision()
#if DEBUG
        SafeInboxLog.bootstrapApplied(
            instance: debugInstanceToken,
            owner: "mergeConversationsFromBootstrap",
            conversationCount: conversations.count,
            forceNetwork: false
        )
#endif
    }

    /// Merge a denormalized server conversation row (legacy REST revalidation only).
    ///
    /// Message-driven inbox updates must use ``patchFromMessage(_:viewerID:...)`` instead.
    func patchFromServerConversation(_ incoming: Conversation) {
        if let existing = conversations.first(where: { $0.id == incoming.id }) {
            var merged = ConversationInboxActivity.mergeConversations(existing: existing, incoming: incoming)
            if activeConversationID == incoming.id {
                merged.unreadCount = 0
                unreadOverrides[incoming.id] = 0
            } else if let override = unreadOverrides[incoming.id] {
                merged.unreadCount = override
            }
            applyConversationUpdate(merged)
        } else {
            var copy = incoming
            if activeConversationID == incoming.id {
                copy.unreadCount = 0
                unreadOverrides[incoming.id] = 0
            }
            applyConversationUpdate(copy)
        }
    }

    enum MessagePatchPolicy: Sendable {
        /// Standard merge — reject stale realtime/bootstrap candidates.
        case canonical
        /// Viewer confirmed send in open thread — always wins for preview/order.
        case confirmedOutgoing
    }

    /// Patch inbox row from a message activity event.
    func patchFromMessage(
        _ message: Message,
        viewerID: ProfileID,
        conversationOpen: Bool = true,
        policy: MessagePatchPolicy = .canonical,
        fallbackConversation: Conversation? = nil,
        source: String = "unknown"
    ) {
#if DEBUG
        SafeInboxLog.patchRequested(
            instance: debugInstanceToken,
            source: source,
            conversationID: message.conversationID,
            messageID: message.id
        )
#endif
        let positionBefore = conversations.firstIndex(where: { $0.id == message.conversationID })
        let previousPreview = conversations.first(where: { $0.id == message.conversationID })?.lastMessagePreview

        let baseConversation = conversations.first(where: { $0.id == message.conversationID })
            ?? fallbackConversation

        guard let baseConversation else {
#if DEBUG
            SafeInboxLog.patchApplied(
                instance: debugInstanceToken,
                source: source,
                conversationID: message.conversationID,
                messageID: message.id,
                previewChanged: false,
                positionBefore: positionBefore,
                positionAfter: positionBefore,
                conversationCount: conversations.count
            )
#endif
            return
        }

        let patched: Conversation?
        switch policy {
        case .confirmedOutgoing:
            patched = ConversationInboxActivity.applyingConfirmedSendActivity(to: baseConversation, message: message)
        case .canonical:
            patched = ConversationInboxActivity.applyingMessageActivity(to: baseConversation, message: message)
        }

        guard let patched else {
#if DEBUG
            let existing = conversations.first(where: { $0.id == message.conversationID })
            SafeInboxLog.activityCompare(
                instance: debugInstanceToken,
                incomingAt: message.createdAt,
                existingAt: existing?.lastMessageAt,
                incomingMessageID: message.id,
                existingMessageID: existing?.lastMessageID,
                accepted: false
            )
            SafeInboxLog.patchApplied(
                instance: debugInstanceToken,
                source: source,
                conversationID: message.conversationID,
                messageID: message.id,
                previewChanged: false,
                positionBefore: positionBefore,
                positionAfter: positionBefore,
                conversationCount: conversations.count
            )
#endif
            return
        }

        var convo = patched
        let isIncoming = message.senderProfileID != viewerID
        let isOpen = conversationOpen || activeConversationID == message.conversationID
        if isIncoming, !isOpen {
            let nextUnread = max(1, unreadCount(for: convo) + 1)
            unreadOverrides[convo.id] = nextUnread
            convo.unreadCount = nextUnread
        } else if !isIncoming || isOpen {
            unreadOverrides[convo.id] = 0
            convo.unreadCount = 0
        }
        applyConversationUpdate(convo)

#if DEBUG
        let positionAfter = conversations.firstIndex(where: { $0.id == message.conversationID })
        let previewChanged = previousPreview != convo.lastMessagePreview
        SafeInboxLog.patchApplied(
            instance: debugInstanceToken,
            source: source,
            conversationID: message.conversationID,
            messageID: message.id,
            previewChanged: previewChanged,
            positionBefore: positionBefore,
            positionAfter: positionAfter,
            conversationCount: conversations.count
        )
#endif
    }

    func replaceRooms(_ items: [TradeRoom], previews: [RoomID: String] = [:], unread: [RoomID: Int] = [:]) {
        let preservedCounts = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0.memberCount) })
        rooms = items.map { item in
            var room = item
            if room.memberCount == nil, let preserved = preservedCounts[item.id] {
                room.memberCount = preserved
            }
            return room
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !previews.isEmpty { roomPreviews.merge(previews) { _, new in new } }
        if !unread.isEmpty {
            var merged = roomUnread
            var nextOverrides = roomUnreadOverrides
            for (id, serverCount) in unread {
                if let override = roomUnreadOverrides[id], serverCount != override {
                    merged[id] = override
                    nextOverrides[id] = override
                } else {
                    merged[id] = serverCount
                    nextOverrides.removeValue(forKey: id)
                }
            }
            roomUnreadOverrides = nextOverrides
            roomUnread = merged
        }
        hasLoadedRooms = true
    }

    func applyMemberCounts(_ counts: [RoomID: Int]) {
        guard !counts.isEmpty else { return }
        rooms = rooms.map { room in
            guard let count = counts[room.id] else { return room }
            var copy = room
            copy.memberCount = count
            return copy
        }
    }

    func updateRoomMemberCount(roomID: RoomID, count: Int?) {
        guard let index = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        rooms[index].memberCount = count
    }

    func applyConversationUpdate(_ conversation: Conversation) {
        guard !hiddenConversationIDs.contains(conversation.id) else { return }
        var conversation = conversation
        if let override = unreadOverrides[conversation.id] {
            if conversation.unreadCount == override {
                unreadOverrides.removeValue(forKey: conversation.id)
            } else {
                conversation.unreadCount = override
            }
        }
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
        }
        if conversation.isPinned {
            pinnedConversationIDs.insert(conversation.id)
        }
        // Web inbox patches re-run `sortConversationsDesc` so the row jumps to the top.
        // Full array reassignment so Observation invalidates inbox rows (unread + sort).
        conversations = Self.sortConversationsDesc(conversations, pinned: pinnedConversationIDs)
        DirectConversationPairIndex.shared.register(conversation: conversation)
        hasLoaded = true
        bumpActivityRevision()
    }

    private func bumpActivityRevision() {
        activityRevision &+= 1
    }

    func upsertConversation(_ conversation: Conversation) {
        applyConversationUpdate(conversation)
    }

    func removeConversation(id: ConversationID, pendingRemoteDelete: Bool = false) {
        hiddenConversationIDs.insert(id)
        if pendingRemoteDelete {
            pendingDeleteConversationIDs.insert(id)
        }
        conversations.removeAll { $0.id == id }
        pinnedConversationIDs.remove(id)
        mutedConversationIDs.remove(id)
        unreadOverrides.removeValue(forKey: id)
        DirectConversationPairIndex.shared.rebuild(from: conversations)
        bumpActivityRevision()
    }

    /// Hide 1:1 threads with a blocked peer — mirrors web hidden blocked DM inbox behavior.
    func removeDirectConversations(with peerID: ProfileID) {
        let ids = conversations.filter { conversation in
            !conversation.isGroup && conversation.participantProfileIDs.contains(peerID)
        }.map(\.id)
        for id in ids {
            removeConversation(id: id)
        }
    }

    func finalizeConversationDelete(id: ConversationID) {
        pendingDeleteConversationIDs.remove(id)
    }

    func cancelPendingConversationDelete(id: ConversationID) {
        pendingDeleteConversationIDs.remove(id)
        hiddenConversationIDs.remove(id)
    }

    /// Restore a conversation after a failed optimistic delete.
    func restoreRemovedConversation(_ conversation: Conversation) {
        hiddenConversationIDs.remove(conversation.id)
        pendingDeleteConversationIDs.remove(conversation.id)
        upsertConversation(conversation)
    }

    func removeRoom(id: RoomID) {
        rooms.removeAll { $0.id == id }
        roomPreviews.removeValue(forKey: id)
        roomUnread.removeValue(forKey: id)
        mutedRoomIDs.remove(id)
    }

    func isMuted(_ id: ConversationID) -> Bool {
        mutedConversationIDs.contains(id)
            || (conversations.first { $0.id == id }?.isMuted ?? false)
    }

    func isPinned(_ id: ConversationID) -> Bool {
        pinnedConversationIDs.contains(id)
    }

    func isTyping(_ id: ConversationID) -> Bool {
        typingConversationIDs.contains(id)
    }

    func isOnline(_ profileID: ProfileID) -> Bool {
        onlineProfileIDs.contains(profileID)
    }

    func isRoomMuted(_ id: RoomID) -> Bool {
        mutedRoomIDs.contains(id)
    }

    func unreadCount(for conversation: Conversation) -> Int {
        unreadOverrides[conversation.id] ?? conversation.unreadCount
    }

    func toggleMute(conversationID: ConversationID) {
        let nextMuted = !isMuted(conversationID)
        applyConversationMute(conversationID: conversationID, isMuted: nextMuted)
    }

    func applyConversationMute(conversationID: ConversationID, isMuted: Bool) {
        if isMuted {
            mutedConversationIDs.insert(conversationID)
        } else {
            mutedConversationIDs.remove(conversationID)
        }
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }
        var updated = conversations
        updated[index].isMuted = isMuted
        if isMuted {
            updated[index].unreadCount = 0
            unreadOverrides[conversationID] = 0
        }
        conversations = updated
    }

    func togglePin(conversationID: ConversationID) {
        if pinnedConversationIDs.contains(conversationID) {
            pinnedConversationIDs.remove(conversationID)
        } else {
            pinnedConversationIDs.insert(conversationID)
        }
        conversations = Self.sortConversationsDesc(conversations, pinned: pinnedConversationIDs)
    }

    func toggleMute(roomID: RoomID) {
        if mutedRoomIDs.contains(roomID) {
            mutedRoomIDs.remove(roomID)
        } else {
            mutedRoomIDs.insert(roomID)
        }
    }

    func markRead(conversationID: ConversationID) {
        unreadOverrides[conversationID] = 0
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }
        // Reassign the array — in-place `conversations[i].unreadCount = 0` does not
        // reliably invalidate SwiftUI Observation subscribers on the inbox list.
        var updated = conversations
        updated[index].unreadCount = 0
        conversations = updated
    }

    /// Drop a failed optimistic unread override so the next server payload wins.
    func dropUnreadOverride(conversationID: ConversationID) {
        unreadOverrides.removeValue(forKey: conversationID)
    }

    func markUnread(conversationID: ConversationID) {
        unreadOverrides[conversationID] = 1
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }
        var updated = conversations
        updated[index].unreadCount = max(1, updated[index].unreadCount)
        conversations = updated
    }

    func markRoomRead(roomID: RoomID) {
        // Reassign the dictionary so Observation invalidates Trade Room / Messages rows.
        roomUnreadOverrides[roomID] = 0
        var updated = roomUnread
        updated[roomID] = 0
        roomUnread = updated
    }

    /// Drop a failed optimistic room-unread override so the restored count can win.
    func dropRoomUnreadOverride(roomID: RoomID) {
        roomUnreadOverrides.removeValue(forKey: roomID)
    }

    func markRoomUnread(roomID: RoomID) {
        roomUnreadOverrides.removeValue(forKey: roomID)
        var updated = roomUnread
        updated[roomID] = max(1, (updated[roomID] ?? 0) + 1)
        roomUnread = updated
    }

    func setRoomUnread(roomID: RoomID, count: Int) {
        let next = max(0, count)
        if let override = roomUnreadOverrides[roomID], next != override {
            // Keep optimistic clear until the server agrees.
            var updated = roomUnread
            updated[roomID] = override
            roomUnread = updated
            return
        }
        if roomUnreadOverrides[roomID] == next {
            roomUnreadOverrides.removeValue(forKey: roomID)
        }
        var updated = roomUnread
        updated[roomID] = next
        roomUnread = updated
    }

    func setActiveConversation(_ conversationID: ConversationID?) {
        activeConversationID = conversationID
    }

    func setActiveRoom(_ roomID: RoomID?) {
        activeRoomID = roomID
    }

    /// Fixture / future realtime hooks for typing + presence.
    func setTyping(_ typing: Bool, conversationID: ConversationID) {
        if typing {
            typingConversationIDs.insert(conversationID)
        } else {
            typingConversationIDs.remove(conversationID)
        }
    }

    func setOnline(_ online: Bool, profileID: ProfileID) {
        if online {
            onlineProfileIDs.insert(profileID)
        } else {
            onlineProfileIDs.remove(profileID)
        }
    }

    func seedLocalPresentation(
        pinned: Set<ConversationID> = [],
        mutedConversations: Set<ConversationID> = [],
        typing: Set<ConversationID> = [],
        online: Set<ProfileID> = [],
        mutedRooms: Set<RoomID> = []
    ) {
        pinnedConversationIDs = pinned
        mutedConversationIDs = mutedConversations
        typingConversationIDs = typing
        onlineProfileIDs = online
        mutedRoomIDs = mutedRooms
        conversations = Self.sortConversationsDesc(conversations, pinned: pinnedConversationIDs)
    }

    /// Clears inbox state when the authenticated user changes (logout / account switch).
    /// Does not disable caching — the next `loadIfNeeded` repopulates for the new session.
    func invalidate() {
        conversations = []
        rooms = []
        roomPreviews = [:]
        roomUnread = [:]
        activeConversationID = nil
        activeRoomID = nil
        hasLoaded = false
        hasLoadedRooms = false
        lastLoadedAt = nil
        mutedConversationIDs = []
        pinnedConversationIDs = []
        mutedRoomIDs = []
        typingConversationIDs = []
        onlineProfileIDs = []
        unreadOverrides = [:]
        roomUnreadOverrides = [:]
        hiddenConversationIDs = []
        pendingDeleteConversationIDs = []
        activityRevision = 0
        DirectConversationPairIndex.shared.invalidate()
    }

#if DEBUG
    func resetForTesting() {
        invalidate()
    }

    func markStaleForTesting() {
        lastLoadedAt = Date().addingTimeInterval(-(MessagingInboxFreshness.softStaleSeconds + 60))
    }

    func seedForTesting(conversationCount: Int) {
        let viewer = ProfileID("viewer-1")
        let peer = ProfileID("peer-1")
        let items = (0..<conversationCount).map { index in
            Conversation(
                id: ConversationID("c-\(index)"),
                participantProfileIDs: [viewer, peer],
                title: "Chat \(index)",
                peerUsername: "peer",
                avatar: nil,
                isGroup: false,
                isPinned: false,
                lastMessagePreview: "hi",
                lastMessageAt: .now,
                lastMessageID: MessageID("m-\(index)"),
                unreadCount: 0,
                isMuted: false,
                updatedAt: .now
            )
        }
        replaceConversations(items)
    }
#endif

    /// Web `sortConversationsDesc` — pinned first, then activity descending with tie-breaks.
    private static func sortConversationsDesc(
        _ items: [Conversation],
        pinned: Set<ConversationID>
    ) -> [Conversation] {
        ConversationInboxActivity.sortConversations(items, pinned: pinned)
    }
}
