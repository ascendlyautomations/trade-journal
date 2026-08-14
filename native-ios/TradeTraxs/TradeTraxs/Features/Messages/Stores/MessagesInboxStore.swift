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
    /// Room currently open in the conversation shell — suppresses inbox unread bumps.
    private(set) var activeRoomID: RoomID?
    private(set) var hasLoaded = false
    /// True after the first member-rooms hydration (Messages or Trade Rooms home).
    private(set) var hasLoadedRooms = false
    private(set) var lastLoadedAt: Date?

    /// Local-only overrides (backend mute/pin APIs are not fully exposed on MessageRepository).
    private var mutedConversationIDs: Set<ConversationID> = []
    private var pinnedConversationIDs: Set<ConversationID> = []
    private var mutedRoomIDs: Set<RoomID> = []
    private var typingConversationIDs: Set<ConversationID> = []
    private var onlineProfileIDs: Set<ProfileID> = []
    private var unreadOverrides: [ConversationID: Int] = [:]
    /// Optimistic room unread clears that must survive bootstrap until the server agrees.
    private var roomUnreadOverrides: [RoomID: Int] = [:]
    private var hiddenConversationIDs: Set<ConversationID> = []

    private init() {}

    /// Web `sortConversationsDesc` order with hidden rows removed.
    var visibleConversations: [Conversation] {
        conversations.filter { !hiddenConversationIDs.contains($0.id) }
    }

    /// Sum of effective DM unread counts — used by Messages inbox UI (not app-icon badge).
    var totalDirectMessageUnread: Int {
        visibleConversations.reduce(0) { partial, conversation in
            partial + unreadCount(for: conversation)
        }
    }

    func replaceConversations(_ items: [Conversation]) {
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
        hasLoaded = true
        lastLoadedAt = .now
    }

    func replaceRooms(_ items: [TradeRoom], previews: [RoomID: String] = [:], unread: [RoomID: Int] = [:]) {
        rooms = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    func applyConversationUpdate(_ conversation: Conversation) {
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
        hiddenConversationIDs.remove(conversation.id)
        // Web inbox patches re-run `sortConversationsDesc` so the row jumps to the top.
        // Full array reassignment so Observation invalidates inbox rows (unread + sort).
        conversations = Self.sortConversationsDesc(conversations, pinned: pinnedConversationIDs)
        hasLoaded = true
    }

    func upsertConversation(_ conversation: Conversation) {
        applyConversationUpdate(conversation)
    }

    func removeConversation(id: ConversationID) {
        hiddenConversationIDs.insert(id)
        conversations.removeAll { $0.id == id }
        pinnedConversationIDs.remove(id)
        mutedConversationIDs.remove(id)
        unreadOverrides.removeValue(forKey: id)
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
        if mutedConversationIDs.contains(conversationID) {
            mutedConversationIDs.remove(conversationID)
        } else {
            mutedConversationIDs.insert(conversationID)
        }
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
    }

#if DEBUG
    func resetForTesting() {
        invalidate()
    }
#endif

    /// Exact web `sortConversationsDesc` — pinned first, then `last_message_at` descending.
    private static func sortConversationsDesc(
        _ items: [Conversation],
        pinned: Set<ConversationID>
    ) -> [Conversation] {
        items.sorted { lhs, rhs in
            let lp = pinned.contains(lhs.id) || lhs.isPinned
            let rp = pinned.contains(rhs.id) || rhs.isPinned
            if lp != rp { return lp && !rp }
            let ld = lhs.lastMessageAt ?? .distantPast
            let rd = rhs.lastMessageAt ?? .distantPast
            return ld > rd
        }
    }
}
