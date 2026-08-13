import Foundation
import Observation

/// Canonical messaging domain owner — one bootstrap, one ``MessagingState``, one realtime loop.
///
/// Messages home and Trade Rooms home are presentation façades over this domain.
/// ``MessagesInboxStore`` remains the mutable presentation cache for badges / previews /
/// conversation thread patches (same product behavior).
@Observable
@MainActor
final class MessagingDomain {
    static let shared = MessagingDomain()

    private(set) var state = MessagingState()
    /// Peer + room-owner profiles resolved during bootstrap (screens read for row presentation).
    private(set) var peerProfiles: [ProfileID: Profile] = [:]

    private var messages: (any MessageRepository)?
    private var rooms: (any RoomRepository)?
    private var profiles: (any ProfileRepository)?
    private var session: (any SessionProviding)?
    private var detailCache: DetailPresentationCache?
    private var realtimeHub: RealtimeHub?
    private let inboxStore = MessagesInboxStore.shared

    private var bootstrapTask: Task<Void, Never>?
    private var readCursorTask: Task<Void, Never>?
    private var roomUnreadTask: Task<Void, Never>?
    private var roomReadCursorTask: Task<Void, Never>?
    private var realtimeRetainCount = 0
    private var isConfigured = false

    private init() {}

    /// Wire repositories (idempotent). Safe to call from Messages and Trade Rooms homes.
    func configure(
        messages: any MessageRepository,
        rooms: any RoomRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        realtimeHub: RealtimeHub?
    ) {
        self.messages = messages
        self.rooms = rooms
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.realtimeHub = realtimeHub
        isConfigured = true
    }

    // MARK: - Standard lifecycle (``ScreenLifecycle``)

    /// Canonical first-paint for Messages home (full inbox).
    func bootstrapIfNeeded() async {
        await bootstrapHomeIfNeeded(forceNetwork: false)
    }

    func refresh() async {
        await refreshHome()
    }

    /// Inbox is not cursor-paginated at the home layer.
    func loadMore() async {}

    /// Prefer ``retainRealtime`` / ``releaseRealtime`` from overlapping homes.
    func subscribeRealtime() {
        Task { await retainRealtime() }
    }

    func unsubscribeRealtime() {
        releaseRealtime()
    }

    // MARK: - Bootstrap

    /// Full inbox bootstrap (Messages home). Concurrent conversations + rooms.
    func bootstrapHomeIfNeeded(forceNetwork: Bool = false) async {
        if !forceNetwork, state.didBootstrap, inboxStore.hasLoaded {
            await syncStateFromInbox()
            return
        }
        if let existing = bootstrapTask, !forceNetwork {
            await existing.value
            await syncStateFromInbox()
            return
        }
        if forceNetwork {
            bootstrapTask?.cancel()
        }

        let task = Task { await performHomeBootstrap(forceNetwork: forceNetwork) }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
    }

    /// Rooms-only bootstrap (Trade Rooms home when inbox not yet loaded).
    func bootstrapRoomsIfNeeded(forceNetwork: Bool = false) async {
        if !forceNetwork, inboxStore.hasLoadedRooms {
            await syncStateFromInbox()
            state.phase = .loaded
            return
        }
        // Prefer waiting on an in-flight full home bootstrap rather than racing rooms-only.
        if let existing = bootstrapTask, !forceNetwork {
            await existing.value
            if inboxStore.hasLoadedRooms {
                await syncStateFromInbox()
                state.phase = .loaded
                return
            }
        }
        if forceNetwork {
            bootstrapTask?.cancel()
        }

        let task = Task { await performRoomsBootstrap(forceNetwork: forceNetwork) }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
    }

    func refreshHome() async {
        state.isRefreshing = true
        await bootstrapHomeIfNeeded(forceNetwork: true)
        state.isRefreshing = false
    }

    func refreshRooms() async {
        state.isRefreshing = true
        await bootstrapRoomsIfNeeded(forceNetwork: true)
        state.isRefreshing = false
    }

    // MARK: - Realtime (domain-owned, retain-counted)

    /// Messages / Trade Rooms homes call this after bootstrap. Single shared watcher set.
    func retainRealtime() async {
        realtimeRetainCount += 1
        await startRealtimeIfNeeded()
    }

    func releaseRealtime() {
        realtimeRetainCount = max(0, realtimeRetainCount - 1)
        if realtimeRetainCount == 0 {
            stopRealtime()
        }
    }

    func invalidate() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        stopRealtime()
        realtimeRetainCount = 0
        state = MessagingState()
        peerProfiles = [:]
        isConfigured = false
        messages = nil
        rooms = nil
        profiles = nil
        session = nil
        detailCache = nil
        realtimeHub = nil
    }

    func profile(id: ProfileID) -> Profile? {
        peerProfiles[id] ?? detailCache?.profile(id: id)
    }

    // MARK: - Private bootstrap

    private func makeContext(forceNetwork: Bool) -> MessagingBootstrap.Context? {
        guard let messages, let rooms, let profiles, let session, let detailCache else {
            return nil
        }
        return MessagingBootstrap.Context(
            messages: messages,
            rooms: rooms,
            profiles: profiles,
            session: session,
            detailCache: detailCache,
            inboxStore: inboxStore,
            forceNetwork: forceNetwork
        )
    }

    private func performHomeBootstrap(forceNetwork: Bool) async {
        guard let context = makeContext(forceNetwork: forceNetwork) else {
            state.phase = .failed("Messaging domain is not configured.")
            return
        }
        if state.phase != .loaded {
            state.phase = .loading
        }
        do {
            let result = try await MessagingBootstrap.loadHome(context)
            apply(result)
            state.phase = .loaded
            state.didBootstrap = true
            state.lastUpdated = Date()
            state.errorMessage = nil
        } catch {
            if inboxStore.hasLoaded {
                await syncStateFromInbox()
                state.phase = .loaded
            } else {
                state.phase = .failed(MessagesInboxSupport.message(for: error))
                state.errorMessage = MessagesInboxSupport.message(for: error)
            }
        }
    }

    private func performRoomsBootstrap(forceNetwork: Bool) async {
        guard let context = makeContext(forceNetwork: forceNetwork) else {
            state.phase = .failed("Messaging domain is not configured.")
            return
        }
        if state.phase != .loaded {
            state.phase = .loading
        }
        do {
            let result = try await MessagingBootstrap.loadRoomsOnly(context)
            apply(result)
            state.phase = .loaded
            state.lastUpdated = Date()
            // Rooms-only does not mark full home bootstrap complete.
            if result.loadedConversations {
                state.didBootstrap = true
            }
            state.errorMessage = nil
        } catch {
            if inboxStore.hasLoadedRooms || !inboxStore.rooms.isEmpty {
                await syncStateFromInbox()
                state.phase = .loaded
            } else {
                state.phase = .failed(MessagesInboxSupport.message(for: error))
                state.errorMessage = MessagesInboxSupport.message(for: error)
            }
        }
    }

    private func apply(_ result: MessagingBootstrap.Result) {
        state.viewerID = result.viewerID
        state.hasLoadedConversations = result.loadedConversations || inboxStore.hasLoaded
        state.hasLoadedRooms = result.loadedRooms || inboxStore.hasLoadedRooms
        for (id, profile) in result.peerProfiles {
            peerProfiles[id] = profile
        }
        // Pull any remaining peers already in detail cache.
        if let viewerID = result.viewerID {
            for conversation in inboxStore.conversations {
                if let peerID = MessagesInboxSupport.peerID(in: conversation, viewerID: viewerID),
                   let cached = detailCache?.profile(id: peerID)
                {
                    peerProfiles[peerID] = cached
                }
            }
        }
        for room in inboxStore.rooms {
            if let owner = detailCache?.profile(id: room.ownerProfileID) {
                peerProfiles[room.ownerProfileID] = owner
            }
        }
    }

    private func syncStateFromInbox() async {
        state.hasLoadedConversations = inboxStore.hasLoaded
        state.hasLoadedRooms = inboxStore.hasLoadedRooms
        if state.viewerID == nil, let session {
            state.viewerID = await session.currentUserID.map { ProfileID($0.rawValue) }
        }
        if let viewerID = state.viewerID {
            for conversation in inboxStore.conversations {
                if let peerID = MessagesInboxSupport.peerID(in: conversation, viewerID: viewerID),
                   let cached = detailCache?.profile(id: peerID)
                {
                    peerProfiles[peerID] = cached
                }
            }
        }
        for room in inboxStore.rooms {
            if let owner = detailCache?.profile(id: room.ownerProfileID) {
                peerProfiles[room.ownerProfileID] = owner
            }
        }
        if inboxStore.hasLoaded || inboxStore.hasLoadedRooms {
            state.phase = .loaded
            if inboxStore.hasLoaded {
                state.didBootstrap = true
            }
        }
    }

    // MARK: - Realtime

    private func startRealtimeIfNeeded() async {
        guard let realtimeHub, let session, let viewerID = state.viewerID else { return }
        guard !MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) else { return }

        // Registry bookkeeping — Messages home channel is the canonical inbox topic.
        try? await realtimeHub.subscriptions.subscribe(
            RealtimeChannelID(kind: .conversation, topic: "inbox")
        )
        try? await realtimeHub.subscriptions.subscribe(
            RealtimeChannelID(kind: .room, topic: "trade-rooms-home")
        )

        await startReadCursorRealtimeIfNeeded(viewerID: viewerID, session: session)
        await startRoomUnreadRealtimeIfNeeded(viewerID: viewerID, session: session)
        await startRoomReadCursorRealtimeIfNeeded(viewerID: viewerID, session: session)
    }

    private func stopRealtime() {
        readCursorTask?.cancel()
        roomUnreadTask?.cancel()
        roomReadCursorTask?.cancel()
        readCursorTask = nil
        roomUnreadTask = nil
        roomReadCursorTask = nil
        Task { [realtimeHub] in
            try? await realtimeHub?.subscriptions.unsubscribe(
                RealtimeChannelID(kind: .conversation, topic: "inbox")
            )
            try? await realtimeHub?.subscriptions.unsubscribe(
                RealtimeChannelID(kind: .room, topic: "trade-rooms-home")
            )
        }
    }

    private func startReadCursorRealtimeIfNeeded(
        viewerID: ProfileID,
        session: any SessionProviding
    ) async {
        guard let realtimeHub, let messages else { return }
        guard readCursorTask == nil else { return }

        readCursorTask = Task { [weak self] in
            guard let self else { return }
            let token = await session.accessToken
            for await signal in realtimeHub.watchConversationReadCursors(
                userID: viewerID.rawValue,
                accessToken: token
            ) {
                guard !Task.isCancelled else { break }
                guard let rawID = signal.conversationID ?? signal.messageID else { continue }
                let conversationID = ConversationID(rawID)
                guard let existing = inboxStore.conversations.first(where: { $0.id == conversationID })
                else { continue }
                let locallyCleared = inboxStore.unreadCount(for: existing) == 0
                if var updated = try? await messages.conversation(id: conversationID) {
                    if locallyCleared { updated.unreadCount = 0 }
                    inboxStore.applyConversationUpdate(updated)
                    if locallyCleared { inboxStore.markRead(conversationID: conversationID) }
                } else if locallyCleared {
                    inboxStore.markRead(conversationID: conversationID)
                }
            }
            readCursorTask = nil
        }
    }

    private func startRoomUnreadRealtimeIfNeeded(
        viewerID: ProfileID,
        session: any SessionProviding
    ) async {
        guard let realtimeHub else { return }
        guard roomUnreadTask == nil else { return }
        let roomIDs = inboxStore.rooms.map(\.id.rawValue)
        guard !roomIDs.isEmpty else { return }

        roomUnreadTask = Task { [weak self] in
            guard let self else { return }
            let token = await session.accessToken
            for await signal in realtimeHub.watchMemberRoomMessages(
                roomIDs: roomIDs,
                accessToken: token
            ) {
                guard !Task.isCancelled else { break }
                guard signal.kind == .insert else { continue }
                guard let rawID = signal.conversationID ?? signal.messageID else { continue }
                let roomID = RoomID(rawID)
                guard inboxStore.rooms.contains(where: { $0.id == roomID }) else { continue }
                guard inboxStore.activeRoomID != roomID else { continue }
                inboxStore.markRoomUnread(roomID: roomID)
            }
            roomUnreadTask = nil
        }
    }

    private func startRoomReadCursorRealtimeIfNeeded(
        viewerID: ProfileID,
        session: any SessionProviding
    ) async {
        guard let realtimeHub, let rooms else { return }
        guard roomReadCursorTask == nil else { return }

        roomReadCursorTask = Task { [weak self] in
            guard let self else { return }
            let token = await session.accessToken
            for await signal in realtimeHub.watchRoomReadCursors(
                userID: viewerID.rawValue,
                accessToken: token
            ) {
                guard !Task.isCancelled else { break }
                guard let rawID = signal.conversationID ?? signal.messageID else { continue }
                let roomID = RoomID(rawID)
                guard inboxStore.rooms.contains(where: { $0.id == roomID }) else { continue }
                let locallyCleared = (inboxStore.roomUnread[roomID] ?? 0) == 0
                if let counts = try? await rooms.unreadCounts(for: [roomID]),
                   let count = counts[roomID]
                {
                    inboxStore.setRoomUnread(roomID: roomID, count: locallyCleared ? 0 : count)
                } else if locallyCleared {
                    inboxStore.markRoomRead(roomID: roomID)
                }
            }
            roomReadCursorTask = nil
        }
    }
}

extension MessagingDomain: ScreenLifecycle, ScreenRealtimeRetaining {}
