import Foundation

/// Viewer-scoped on-disk snapshots for Messages, Activity, and Trade Rooms.
///
/// Presentation-only — server + RLS remain authoritative for protected actions.
nonisolated enum SocialDiskCache {
    static let folderName = "SocialDiskCache"

    // MARK: - Bounds

    static let maxInboxConversations = 40
    static let maxDMThreads = 10
    static let maxMessagesPerDMThread = 50
    static let maxMemberRooms = 50
    static let maxRoomSnapshots = 5
    static let maxMessagesPerRoomChannel = 50
    static let maxActivityItems = 50

    // MARK: - Blobs

    struct InboxBlob: Codable, Sendable {
        var viewerID: String
        var savedAt: Date
        var conversations: [Conversation]
        var rooms: [TradeRoom]
        var roomPreviews: [String: String]
        var roomActivityAt: [String: Date]
        var roomUnread: [String: Int]
        var unreadOverrides: [String: Int]
        var pinnedConversationIDs: [String]
        var mutedConversationIDs: [String]
        var mutedRoomIDs: [String]
    }

    struct DMThreadBlob: Codable, Sendable {
        var viewerID: String
        var conversationID: String
        var savedAt: Date
        var lastAccessedAt: Date
        var conversation: Conversation
        var messages: [Message]
        var nextCursor: String?
        var hasMoreMessages: Bool
        var contentGeneration: UInt64
    }

    struct MemberRoomsBlob: Codable, Sendable {
        var viewerID: String
        var savedAt: Date
        var rooms: [TradeRoom]
        var unread: [String: Int]
        var activityAt: [String: Date]
    }

    struct RoomChannelThreadBlob: Codable, Sendable {
        var channelID: String
        var messages: [Message]
        var nextOlderCursor: String?
        var hasMoreOlder: Bool
        var isLoaded: Bool
    }

    struct RoomSnapshotBlob: Codable, Sendable {
        var viewerID: String
        var roomID: String
        var savedAt: Date
        var lastAccessedAt: Date
        var room: TradeRoom
        var membership: RoomMembership?
        var channels: [RoomChannel]
        var selectedChannelID: String?
        var channelThreads: [String: RoomChannelThreadBlob]
    }

    struct ActivityBlob: Codable, Sendable {
        var viewerID: String
        var savedAt: Date
        var items: [ActivityNotification]
        var unreadCount: Int
        var pendingFollowRequestCount: Int
        var nextCursor: String?
    }

    // MARK: - Inbox

    static func saveInbox(_ blob: InboxBlob) {
        var capped = blob
        capped.conversations = Array(blob.conversations.prefix(maxInboxConversations))
        capped.rooms = Array(blob.rooms.prefix(maxMemberRooms))
        write(capped, file: "inbox-\(blob.viewerID).json")
    }

    static func loadInbox(for viewerID: ProfileID) -> InboxBlob? {
        read(file: "inbox-\(viewerID.rawValue).json")
    }

    // MARK: - DM threads

    static func saveDMThread(_ blob: DMThreadBlob) {
        var capped = blob
        capped.messages = Array(
            ConversationMessageMerge.sortByCreatedAt(blob.messages).suffix(maxMessagesPerDMThread)
        )
        write(capped, file: dmThreadFile(viewerID: blob.viewerID, conversationID: blob.conversationID))
        enforceDMThreadLimit(viewerID: blob.viewerID)
    }

    static func loadDMThread(viewerID: ProfileID, conversationID: ConversationID) -> DMThreadBlob? {
        read(file: dmThreadFile(viewerID: viewerID.rawValue, conversationID: conversationID.rawValue))
    }

    static func removeDMThread(viewerID: ProfileID, conversationID: ConversationID) {
        remove(file: dmThreadFile(viewerID: viewerID.rawValue, conversationID: conversationID.rawValue))
    }

    // MARK: - Member rooms

    static func saveMemberRooms(_ blob: MemberRoomsBlob) {
        var capped = blob
        capped.rooms = Array(blob.rooms.prefix(maxMemberRooms))
        write(capped, file: "member-rooms-\(blob.viewerID).json")
    }

    static func loadMemberRooms(for viewerID: ProfileID) -> MemberRoomsBlob? {
        read(file: "member-rooms-\(viewerID.rawValue).json")
    }

    // MARK: - Room snapshots

    static func saveRoomSnapshot(_ blob: RoomSnapshotBlob) {
        var capped = blob
        capped.channelThreads = blob.channelThreads.mapValues { thread in
            var copy = thread
            copy.messages = Array(
                ConversationMessageMerge.sortByCreatedAt(thread.messages).suffix(maxMessagesPerRoomChannel)
            )
            return copy
        }
        write(capped, file: roomSnapshotFile(viewerID: blob.viewerID, roomID: blob.roomID))
        enforceRoomSnapshotLimit(viewerID: blob.viewerID)
    }

    static func loadRoomSnapshot(viewerID: ProfileID, roomID: RoomID) -> RoomSnapshotBlob? {
        read(file: roomSnapshotFile(viewerID: viewerID.rawValue, roomID: roomID.rawValue))
    }

    static func removeRoomSnapshot(viewerID: ProfileID, roomID: RoomID) {
        remove(file: roomSnapshotFile(viewerID: viewerID.rawValue, roomID: roomID.rawValue))
    }

    // MARK: - Activity

    static func saveActivity(_ blob: ActivityBlob) {
        var capped = blob
        capped.items = Array(
            blob.items.sorted { $0.createdAt > $1.createdAt }.prefix(maxActivityItems)
        )
        write(capped, file: "activity-\(blob.viewerID).json")
    }

    static func loadActivity(for viewerID: ProfileID) -> ActivityBlob? {
        read(file: "activity-\(viewerID.rawValue).json")
    }

    // MARK: - Session isolation

    static func clear(viewerID: ProfileID) {
        remove(file: "inbox-\(viewerID.rawValue).json")
        remove(file: "member-rooms-\(viewerID.rawValue).json")
        remove(file: "activity-\(viewerID.rawValue).json")
        removeMatching(prefix: "dm-thread-\(viewerID.rawValue)-")
        removeMatching(prefix: "room-thread-\(viewerID.rawValue)-")
    }

    static func clearAll() {
        guard let dir = directoryURL() else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - LRU enforcement

    private static func enforceDMThreadLimit(viewerID: String) {
        guard let dir = directoryURL() else { return }
        let prefix = "dm-thread-\(viewerID)-"
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let threadFiles = urls.filter { $0.lastPathComponent.hasPrefix(prefix) }
        guard threadFiles.count > maxDMThreads else { return }

        let ranked: [(URL, Date)] = threadFiles.compactMap { url in
            guard let blob: DMThreadBlob = readURL(url) else { return nil }
            return (url, blob.lastAccessedAt)
        }
        .sorted { $0.1 < $1.1 }

        for entry in ranked.prefix(ranked.count - maxDMThreads) {
            try? FileManager.default.removeItem(at: entry.0)
        }
    }

    private static func enforceRoomSnapshotLimit(viewerID: String) {
        guard let dir = directoryURL() else { return }
        let prefix = "room-thread-\(viewerID)-"
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let roomFiles = urls.filter { $0.lastPathComponent.hasPrefix(prefix) }
        guard roomFiles.count > maxRoomSnapshots else { return }

        let ranked: [(URL, Date)] = roomFiles.compactMap { url in
            guard let blob: RoomSnapshotBlob = readURL(url) else { return nil }
            return (url, blob.lastAccessedAt)
        }
        .sorted { $0.1 < $1.1 }

        for entry in ranked.prefix(ranked.count - maxRoomSnapshots) {
            try? FileManager.default.removeItem(at: entry.0)
        }
    }

    // MARK: - IO

    private static func dmThreadFile(viewerID: String, conversationID: String) -> String {
        "dm-thread-\(viewerID)-\(conversationID).json"
    }

    private static func roomSnapshotFile(viewerID: String, roomID: String) -> String {
        "room-thread-\(viewerID)-\(roomID).json"
    }

    private static func directoryURL() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func write<T: Encodable>(_ value: T, file: String) {
        guard let dir = directoryURL() else { return }
        let url = dir.appendingPathComponent(sanitize(file))
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Soft-fail — disk cache must never break networking.
        }
    }

    private static func read<T: Decodable>(file: String) -> T? {
        guard let dir = directoryURL() else { return nil }
        let url = dir.appendingPathComponent(sanitize(file))
        return readURL(url)
    }

    private static func readURL<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func remove(file: String) {
        guard let dir = directoryURL() else { return }
        let url = dir.appendingPathComponent(sanitize(file))
        try? FileManager.default.removeItem(at: url)
    }

    private static func removeMatching(prefix: String) {
        guard let dir = directoryURL() else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
    }
}
