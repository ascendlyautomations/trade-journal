import Foundation
import Observation

/// Session-scoped member Trade Rooms — single-flight across Messages + Trade Rooms home.
@Observable
@MainActor
final class SessionMemberRoomsStore {
    static let shared = SessionMemberRoomsStore()

    private var roomsByViewer: [ProfileID: [TradeRoom]] = [:]
    private var unreadByViewer: [ProfileID: [RoomID: Int]] = [:]
    private var activityAtByViewer: [ProfileID: [RoomID: Date]] = [:]
    private var inFlight: [ProfileID: Task<([TradeRoom], [RoomID: Int], [RoomID: Date]), Error>] = [:]
    private var loadedAt: [ProfileID: Date] = [:]

    private let freshTTL: TimeInterval = 5 * 60

    private init() {}

    func cached(for viewerID: ProfileID) -> ([TradeRoom], [RoomID: Int], [RoomID: Date])? {
        guard let rooms = roomsByViewer[viewerID] else { return nil }
        return (rooms, unreadByViewer[viewerID] ?? [:], activityAtByViewer[viewerID] ?? [:])
    }

    func isFresh(for viewerID: ProfileID, now: Date = Date()) -> Bool {
        guard let loaded = loadedAt[viewerID], roomsByViewer[viewerID] != nil else { return false }
        return now.timeIntervalSince(loaded) < freshTTL
    }

    /// Cache-first. Concurrent callers share one `memberRooms` + unread fetch.
    func memberRooms(
        for viewerID: ProfileID,
        repository: any RoomRepository,
        forceNetwork: Bool = false
    ) async throws -> ([TradeRoom], [RoomID: Int], [RoomID: Date]) {
        if !forceNetwork, let cached = cached(for: viewerID), isFresh(for: viewerID) {
            SessionNetworkProbe.record(
                .cacheHit,
                resource: "rooms.member",
                detail: viewerID.rawValue
            )
            return cached
        }

        if !forceNetwork, roomsByViewer[viewerID] == nil,
           SocialPersistedCacheCoordinator.hydrateMemberRooms(
               viewerID: viewerID,
               inboxStore: MessagesInboxStore.shared,
               memberRoomsStore: .shared
           )
        {
            if let cached = cached(for: viewerID) {
                Task {
                    _ = try? await self.memberRooms(for: viewerID, repository: repository, forceNetwork: true)
                }
                return cached
            }
        }

        if let existing = inFlight[viewerID] {
            SessionNetworkProbe.record(
                .requestCoalesced,
                resource: "rooms.member",
                detail: viewerID.rawValue
            )
            return try await existing.value
        }

        SessionNetworkProbe.record(
            forceNetwork ? .cacheInvalidated : .cacheMiss,
            resource: "rooms.member",
            detail: viewerID.rawValue
        )
        SessionNetworkProbe.record(
            .networkFetch,
            resource: "rooms.member",
            detail: viewerID.rawValue
        )

        let task = Task { () -> ([TradeRoom], [RoomID: Int], [RoomID: Date]) in
            let rooms = try await repository.memberRooms(
                for: viewerID,
                page: PageRequest(limit: 50)
            ).items
            let roomIDs = rooms.map(\.id)
            async let unreadTask = repository.unreadCounts(for: roomIDs)
            async let countsTask = repository.activeMemberCounts(for: roomIDs)
            async let activityTask = repository.lastMessageActivity(for: roomIDs)
            let unread = (try? await unreadTask) ?? [:]
            let counts = (try? await countsTask) ?? [:]
            let activity = (try? await activityTask) ?? [:]
            let enriched = rooms.map { room -> TradeRoom in
                var copy = room
                if let count = counts[room.id] {
                    copy.memberCount = count
                }
                return copy
            }
            return (enriched, unread, activity)
        }
        inFlight[viewerID] = task
        defer { inFlight[viewerID] = nil }

        let loaded = try await task.value
        seed(rooms: loaded.0, unread: loaded.1, activityAt: loaded.2, for: viewerID)
        return loaded
    }

    func seed(
        rooms: [TradeRoom],
        unread: [RoomID: Int],
        activityAt: [RoomID: Date] = [:],
        for viewerID: ProfileID,
        savedAt: Date = Date()
    ) {
        roomsByViewer[viewerID] = rooms
        unreadByViewer[viewerID] = unread
        activityAtByViewer[viewerID] = activityAt
        loadedAt[viewerID] = savedAt
        SocialPersistedCacheCoordinator.persistMemberRooms(viewerID: viewerID, from: self)
    }

    func snapshotForPersistence(viewerID: ProfileID) -> (rooms: [TradeRoom], unread: [RoomID: Int], activityAt: [RoomID: Date])? {
        guard let rooms = roomsByViewer[viewerID] else { return nil }
        return (rooms, unreadByViewer[viewerID] ?? [:], activityAtByViewer[viewerID] ?? [:])
    }

    func applyMemberCounts(_ counts: [RoomID: Int], for viewerID: ProfileID) {
        guard var rooms = roomsByViewer[viewerID], !counts.isEmpty else { return }
        rooms = rooms.map { room in
            guard let count = counts[room.id] else { return room }
            var copy = room
            copy.memberCount = count
            return copy
        }
        roomsByViewer[viewerID] = rooms
    }

    func applyMemberCountDelta(roomID: RoomID, delta: Int, for viewerID: ProfileID) {
        guard delta != 0, var rooms = roomsByViewer[viewerID],
              let index = rooms.firstIndex(where: { $0.id == roomID })
        else { return }
        let current = rooms[index].memberCount ?? 0
        rooms[index].memberCount = max(0, current + delta)
        roomsByViewer[viewerID] = rooms
    }

    func invalidate(viewerID: ProfileID? = nil) {
        if let viewerID {
            roomsByViewer[viewerID] = nil
            unreadByViewer[viewerID] = nil
            activityAtByViewer[viewerID] = nil
            loadedAt[viewerID] = nil
            inFlight[viewerID]?.cancel()
            inFlight[viewerID] = nil
        } else {
            roomsByViewer = [:]
            unreadByViewer = [:]
            activityAtByViewer = [:]
            loadedAt = [:]
            inFlight.values.forEach { $0.cancel() }
            inFlight = [:]
        }
        SessionNetworkProbe.record(
            .cacheInvalidated,
            resource: "rooms.member",
            detail: viewerID?.rawValue ?? "all"
        )
    }
}
