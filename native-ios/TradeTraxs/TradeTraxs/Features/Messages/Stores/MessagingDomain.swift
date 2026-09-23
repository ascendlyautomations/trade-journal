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
    private var rpc: (any RPCClient)?
    private let inboxStore = MessagesInboxStore.shared

    private var bootstrapTask: Task<Void, Never>?
    private var catchUpTask: Task<Void, Never>?
    private var revalidationTask: Task<Void, Never>?
    private var readCursorTask: Task<Void, Never>?
    private var roomUnreadTask: Task<Void, Never>?
    private var roomReadCursorTask: Task<Void, Never>?
    private var roomMemberCountTask: Task<Void, Never>?
    private var inboxMessagesTask: Task<Void, Never>?
    private var readCursorRealtimeConsumer: RealtimeRouteConsumerHandle?
    private var roomUnreadRealtimeConsumer: RealtimeRouteConsumerHandle?
    private var roomReadCursorRealtimeConsumer: RealtimeRouteConsumerHandle?
    private var roomMemberCountRealtimeConsumer: RealtimeRouteConsumerHandle?
    private var inboxMessagesRealtimeConsumer: RealtimeRouteConsumerHandle?
    private var realtimeRetainCount = 0
    private var isConfigured = false
    private var loadGeneration: UInt64 = 0
    private var homeScreenVisible = false
    private var lastHomeRevalidationAt: Date?

    private init() {}

    /// Wire repositories (idempotent). Safe to call from Messages and Trade Rooms homes.
    func configure(
        messages: any MessageRepository,
        rooms: any RoomRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        realtimeHub: RealtimeHub?,
        rpc: (any RPCClient)? = nil
    ) {
        self.messages = messages
        self.rooms = rooms
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.realtimeHub = realtimeHub
        self.rpc = rpc
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

    /// Full inbox bootstrap (Messages home). Concurrent callers share one in-flight task.
    func bootstrapHomeIfNeeded(forceNetwork: Bool = false) async {
        homeScreenVisible = true
        if !forceNetwork, state.didBootstrap, inboxStore.hasLoaded {
            await syncStateFromInbox()
            scheduleSoftRevalidationIfNeeded()
            return
        }
        if !forceNetwork, inboxStore.hasLoaded, state.didBootstrap {
            await syncStateFromInbox()
            scheduleSoftRevalidationIfNeeded()
            return
        }
        if let existing = bootstrapTask {
            await existing.value
            await syncStateFromInbox()
            return
        }

        loadGeneration &+= 1
        if forceNetwork {
            revalidationTask?.cancel()
            revalidationTask = nil
        }

        let generation = loadGeneration
        let task = Task { [generation] in
            await performHomeBootstrap(forceNetwork: forceNetwork, generation: generation, owner: "MessagingDomain.home")
        }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
        await syncStateFromInbox()
    }

    func setHomeScreenVisible(_ visible: Bool) {
        homeScreenVisible = visible
        if !visible {
            revalidationTask?.cancel()
            revalidationTask = nil
        }
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
            loadGeneration &+= 1
        }

        if let existing = bootstrapTask {
            await existing.value
            if inboxStore.hasLoadedRooms {
                await syncStateFromInbox()
                state.phase = .loaded
                return
            }
        }

        let generation = loadGeneration
        let task = Task { [generation] in
            await performRoomsBootstrap(forceNetwork: forceNetwork, generation: generation)
        }
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

    /// Phase 10F — bounded inbox catch-up after Realtime reconnect (existing loader, no thread fan-out).
    func repairInboxAfterReconnect(expectedViewerGeneration: UInt64) async {
        guard let session else { return }
        guard let userID = await session.currentUserID else { return }
        let viewerID = state.viewerID ?? ProfileID(userID.rawValue)
        guard state.viewerID == nil || state.viewerID == viewerID else { return }
        _ = expectedViewerGeneration
        guard inboxStore.hasLoaded else { return }
        let generation = loadGeneration
        guard let rpc else { return }
        await performInboxCatchUp(
            viewerID: viewerID,
            rpc: rpc,
            generation: generation,
            owner: "MessagingDomain.reconnectRepair"
        )
    }

    func invalidate() {
        loadGeneration &+= 1
        bootstrapTask?.cancel()
        bootstrapTask = nil
        catchUpTask?.cancel()
        catchUpTask = nil
        revalidationTask?.cancel()
        revalidationTask = nil
        stopRealtime()
        realtimeRetainCount = 0
        MessagingRealtimeDeliveryCoordinator.resetSession()
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

    private func performHomeBootstrap(
        forceNetwork: Bool,
        generation: UInt64,
        owner: String
    ) async {
        guard let context = makeContext(forceNetwork: forceNetwork) else {
            applyTerminalFailure("Messaging domain is not configured.", generation: generation)
            return
        }
        var hydratedFromDisk = false
        if let session, let userID = await session.currentUserID, !forceNetwork, !inboxStore.hasLoaded {
            let viewer = ProfileID(userID.rawValue)
            hydratedFromDisk = SocialPersistedCacheCoordinator.hydrateInbox(viewerID: viewer, inboxStore: inboxStore)
            if hydratedFromDisk {
                inboxStore.setPersistedViewerID(viewer)
                _ = SocialPersistedCacheCoordinator.hydrateMemberRooms(
                    viewerID: viewer,
                    inboxStore: inboxStore,
                    memberRoomsStore: SessionMemberRoomsStore.shared
                )
                markLoaded(generation: generation)
                state.viewerID = viewer
            }
        }

        if state.phase != .loaded || !inboxStore.hasLoaded {
            if !hydratedFromDisk {
                state.phase = .loading
            }
        }
        do {
            if BackendV2FeatureFlags.isEnabled(.messages),
               let rpc,
               let session,
               let userID = await session.currentUserID
            {
                let viewer = ProfileID(userID.rawValue)
                if DemoExperienceSupport.usesExploreDemoInbox(viewer) {
                    let result = try await MessagingBootstrap.loadHome(context)
                    guard generation == loadGeneration else { return }
                    apply(result)
                    markLoaded(generation: generation)
                    return
                }
                inboxStore.setPersistedViewerID(viewer)

                if hydratedFromDisk, !forceNetwork {
                    catchUpTask?.cancel()
                    catchUpTask = Task { [generation] in
                        await self.performInboxCatchUp(
                            viewerID: viewer,
                            rpc: rpc,
                            generation: generation,
                            owner: owner
                        )
                    }
                    return
                }

                do {
                    _ = try await MessagingBootstrapLoader.loadInbox(
                        viewerID: viewer,
                        rpc: rpc,
                        inboxStore: inboxStore,
                        detailCache: detailCache!,
                        forceNetwork: forceNetwork,
                        loadGeneration: generation,
                        currentGeneration: { [weak self] in self?.loadGeneration ?? 0 },
                        owner: owner,
                        viewVisible: homeScreenVisible
                    )
                    guard generation == loadGeneration else { return }
                    async let roomsTask = SessionMemberRoomsStore.shared.memberRooms(
                        for: viewer,
                        repository: rooms!,
                        forceNetwork: forceNetwork
                    )
                    let (memberRooms, roomUnread, roomActivityAt) = try await roomsTask
                    guard generation == loadGeneration else { return }
                    inboxStore.replaceRooms(memberRooms, activityAt: roomActivityAt, unread: roomUnread)
                    peerProfiles = [:]
                    markLoaded(generation: generation)
                    return
                } catch is MessagingBootstrapLoader.LoaderError {
                    if inboxStore.hasLoaded {
                        await markLoadedFromCache(generation: generation)
                        return
                    }
                } catch {
                    if await applyBenignOrCachedFailure(error, generation: generation) { return }
                    throw error
                }
            }

            guard !inboxStore.hasLoaded else {
                await markLoadedFromCache(generation: generation)
                return
            }

            let result = try await MessagingBootstrap.loadHome(context)
            guard generation == loadGeneration else { return }
            apply(result)
            markLoaded(generation: generation)
        } catch {
            _ = await applyBenignOrCachedFailure(error, generation: generation)
        }
    }

    private func performRoomsBootstrap(forceNetwork: Bool, generation: UInt64) async {
        guard let context = makeContext(forceNetwork: forceNetwork) else {
            applyTerminalFailure("Messaging domain is not configured.", generation: generation)
            return
        }
        if state.phase != .loaded {
            state.phase = .loading
        }
        do {
            let result = try await MessagingBootstrap.loadRoomsOnly(context)
            guard generation == loadGeneration else { return }
            apply(result)
            state.phase = .loaded
            state.lastUpdated = Date()
            if result.loadedConversations {
                state.didBootstrap = true
            }
            state.errorMessage = nil
        } catch {
            if inboxStore.hasLoadedRooms || !inboxStore.rooms.isEmpty {
                await syncStateFromInbox()
                state.phase = .loaded
            } else {
                let benign = await applyBenignOrCachedFailure(error, generation: generation)
                if !benign {
                    applyTerminalFailure(MessagesInboxSupport.message(for: error), generation: generation)
                }
            }
        }
    }

    private func performInboxCatchUp(
        viewerID: ProfileID,
        rpc: any RPCClient,
        generation: UInt64,
        owner: String
    ) async {
        guard generation == loadGeneration else { return }
        guard let rooms else { return }
        do {
            _ = try await MessagingBootstrapLoader.loadInbox(
                viewerID: viewerID,
                rpc: rpc,
                inboxStore: inboxStore,
                detailCache: detailCache!,
                forceNetwork: false,
                loadGeneration: generation,
                currentGeneration: { [weak self] in self?.loadGeneration ?? 0 },
                owner: "\(owner).catchUp"
            )
            guard generation == loadGeneration else { return }
            let (memberRooms, roomUnread, roomActivityAt) = try await SessionMemberRoomsStore.shared.memberRooms(
                for: viewerID,
                repository: rooms,
                forceNetwork: false
            )
            guard generation == loadGeneration else { return }
            inboxStore.replaceRooms(memberRooms, activityAt: roomActivityAt, unread: roomUnread)
            markLoaded(generation: generation)
        } catch {
            if inboxStore.hasLoaded {
                await markLoadedFromCache(generation: generation)
            }
        }
    }

    private func scheduleSoftRevalidationIfNeeded() {
        guard homeScreenVisible else { return }
        guard !inboxStore.hasPendingConversationDeletes else { return }
        guard MessagingInboxFreshness.isSoftStale(lastLoadedAt: inboxStore.lastLoadedAt) else { return }
        guard revalidationTask == nil, bootstrapTask == nil else { return }
        if let lastHomeRevalidationAt,
           Date().timeIntervalSince(lastHomeRevalidationAt) < MessagingInboxFreshness.softStaleSeconds
        {
            return
        }
        let generation = loadGeneration
        revalidationTask = Task { [generation] in
            await performHomeBootstrap(forceNetwork: true, generation: generation, owner: "MessagingDomain.revalidate")
            lastHomeRevalidationAt = Date()
            revalidationTask = nil
        }
    }

    private func markLoaded(generation: UInt64) {
        guard generation == loadGeneration else { return }
        state.phase = .loaded
        state.didBootstrap = true
        state.lastUpdated = Date()
        state.errorMessage = nil
    }

    private func markLoadedFromCache(generation: UInt64) async {
        guard generation == loadGeneration else { return }
        await syncStateFromInbox()
        state.errorMessage = nil
    }

    @discardableResult
    private func applyBenignOrCachedFailure(_ error: Error, generation: UInt64) async -> Bool {
        let diagnostic = MessagesBootstrapFailureDiagnostic.make(error: error)
        if diagnostic.isBenignForUI {
            return true
        }
        if generation != loadGeneration {
            return true
        }
        if inboxStore.hasLoaded {
            await markLoadedFromCache(generation: generation)
            return true
        }
        if bootstrapTask != nil || revalidationTask != nil {
            if state.phase != .loaded {
                state.phase = .loading
            }
            return true
        }
        applyTerminalFailure(MessagesInboxSupport.message(for: error), generation: generation)
        return true
    }

    private func applyTerminalFailure(_ message: String, generation: UInt64) {
        guard generation == loadGeneration else { return }
        guard !inboxStore.hasLoaded else {
            state.phase = .loaded
            state.errorMessage = nil
            return
        }
        if bootstrapTask != nil {
            state.phase = .loading
            return
        }
        state.phase = .failed(message)
        state.errorMessage = message
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
        guard !ExploreModeSupport.isActive else { return }
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
        await startRoomMemberCountRealtimeIfNeeded(viewerID: viewerID, session: session)
        await startInboxMessagesRealtimeIfNeeded(viewerID: viewerID, session: session)
#if DEBUG
        SocialCacheProbe.setRealtimeSubscribed(true)
#endif
    }

    private func stopRealtime() {
        readCursorTask?.cancel()
        roomUnreadTask?.cancel()
        roomReadCursorTask?.cancel()
        roomMemberCountTask?.cancel()
        inboxMessagesTask?.cancel()
        readCursorTask = nil
        roomUnreadTask = nil
        roomReadCursorTask = nil
        roomMemberCountTask = nil
        inboxMessagesTask = nil
        let readConsumer = readCursorRealtimeConsumer
        let roomUnreadConsumer = roomUnreadRealtimeConsumer
        let roomReadConsumer = roomReadCursorRealtimeConsumer
        let memberCountConsumer = roomMemberCountRealtimeConsumer
        let inboxConsumer = inboxMessagesRealtimeConsumer
        readCursorRealtimeConsumer = nil
        roomUnreadRealtimeConsumer = nil
        roomReadCursorRealtimeConsumer = nil
        roomMemberCountRealtimeConsumer = nil
        inboxMessagesRealtimeConsumer = nil
        Task { [realtimeHub] in
            try? await realtimeHub?.subscriptions.unsubscribe(
                RealtimeChannelID(kind: .conversation, topic: "inbox")
            )
            try? await realtimeHub?.subscriptions.unsubscribe(
                RealtimeChannelID(kind: .room, topic: "trade-rooms-home")
            )
            await realtimeHub?.releaseWatch(readConsumer)
            await realtimeHub?.releaseWatch(roomReadConsumer)
            await realtimeHub?.releaseWatch(roomUnreadConsumer)
            await realtimeHub?.releaseWatch(memberCountConsumer)
            await realtimeHub?.releaseWatch(inboxConsumer)
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
            let watch = realtimeHub.watchConversationReadCursors(
                userID: viewerID.rawValue,
                accessToken: token,
                debugOwner: "MessagingDomain.dmRead"
            )
            readCursorRealtimeConsumer = watch.consumer
            for await signal in watch.events {
                guard !Task.isCancelled else { break }
                guard let rawID = signal.conversationID ?? signal.messageID else { continue }
                let conversationID = ConversationID(rawID)
                guard let existing = inboxStore.conversations.first(where: { $0.id == conversationID })
                else { continue }
                let locallyCleared = inboxStore.unreadCount(for: existing) == 0
                if BackendV2FeatureFlags.isEnabled(.messages) {
                    if locallyCleared {
                        inboxStore.markRead(conversationID: conversationID)
                    } else if signal.recordPayload != nil {
#if DEBUG
                        MessagingRealtimeDebugLog.readStatePatch(
                            domain: "dm",
                            id: conversationID.rawValue
                        )
#endif
                        inboxStore.markRead(conversationID: conversationID)
                    }
                    continue
                }
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
            let watch = realtimeHub.watchMemberRoomMessages(
                roomIDs: roomIDs,
                accessToken: token,
                debugOwner: "MessagingDomain.memberRooms"
            )
            roomUnreadRealtimeConsumer = watch.consumer
            for await signal in watch.events {
                guard !Task.isCancelled else { break }
                guard signal.kind == .insert else { continue }
                guard let rawID = signal.conversationID ?? signal.messageID else { continue }
                let roomID = RoomID(rawID)
                guard inboxStore.rooms.contains(where: { $0.id == roomID }) else { continue }
                if inboxStore.activeRoomID == roomID {
#if DEBUG
                    MessagingRealtimeDebugLog.roomOpenSuppressUnread(roomID: rawID)
#endif
                    continue
                }
                if let messageID = signal.messageID,
                   !MessagingRealtimeDeliveryCoordinator.claimMessageInsert(
                       domain: "member-rooms",
                       messageID: messageID,
                       conversationID: rawID
                   )
                {
                    continue
                }
                inboxStore.markRoomUnread(roomID: roomID)
#if DEBUG
                MessagingRealtimeDebugLog.roomUnreadPatch(roomID: rawID, delta: 1)
#endif
            }
            roomUnreadTask = nil
        }
    }

    private func startRoomMemberCountRealtimeIfNeeded(
        viewerID: ProfileID,
        session: any SessionProviding
    ) async {
        guard let realtimeHub, let rooms else { return }
        guard roomMemberCountTask == nil else { return }
        let roomIDs = inboxStore.rooms.map(\.id.rawValue)
        guard !roomIDs.isEmpty else { return }

        roomMemberCountTask = Task { [weak self] in
            guard let self else { return }
            let token = await session.accessToken
            let watch = realtimeHub.watchMemberRoomMembership(
                roomIDs: roomIDs,
                accessToken: token,
                debugOwner: "MessagingDomain.roomMembership"
            )
            roomMemberCountRealtimeConsumer = watch.consumer
            for await signal in watch.events {
                guard !Task.isCancelled else { break }
                guard let payload = signal.recordPayload,
                      let record = PostgresChangeRecordCodec.dictionary(from: payload),
                      let rawRoomID = record["room_id"] as? String
                else { continue }
                let roomID = RoomID(rawRoomID)
                guard inboxStore.rooms.contains(where: { $0.id == roomID }) else { continue }
                if let delta = RoomMemberCountRealtimeSemantics.membershipDelta(
                    kind: signal.kind,
                    record: record,
                    oldRecord: nil
                ) {
                    inboxStore.applyMemberCountDelta(roomID: roomID, delta: delta)
                    SessionMemberRoomsStore.shared.applyMemberCountDelta(
                        roomID: roomID,
                        delta: delta,
                        for: viewerID
                    )
                } else if let counts = try? await rooms.activeMemberCounts(for: [roomID]),
                          let count = counts[roomID]
                {
#if DEBUG
                    MessagingRealtimeDebugLog.networkFallback(reason: "room_member_bounded_reconcile")
#endif
                    inboxStore.updateRoomMemberCount(roomID: roomID, count: count)
                    SessionMemberRoomsStore.shared.applyMemberCounts(counts, for: viewerID)
                }
            }
            roomMemberCountTask = nil
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
            let watch = realtimeHub.watchRoomReadCursors(
                userID: viewerID.rawValue,
                accessToken: token,
                debugOwner: "MessagingDomain.roomRead"
            )
            roomReadCursorRealtimeConsumer = watch.consumer
            for await signal in watch.events {
                guard !Task.isCancelled else { break }
                guard let rawID = signal.conversationID ?? signal.messageID else { continue }
                let roomID = RoomID(rawID)
                guard inboxStore.rooms.contains(where: { $0.id == roomID }) else { continue }
                let locallyCleared = (inboxStore.roomUnread[roomID] ?? 0) == 0
                if locallyCleared {
                    inboxStore.markRoomRead(roomID: roomID)
#if DEBUG
                    MessagingRealtimeDebugLog.readStatePatch(domain: "room", id: roomID.rawValue)
#endif
                } else if signal.recordPayload == nil,
                          let counts = try? await rooms.unreadCounts(for: [roomID]),
                          let count = counts[roomID]
                {
#if DEBUG
                    MessagingRealtimeDebugLog.networkFallback(reason: "room_read_unread_reconcile")
#endif
                    inboxStore.setRoomUnread(roomID: roomID, count: count)
                }
            }
            roomReadCursorTask = nil
        }
    }

    private func startInboxMessagesRealtimeIfNeeded(
        viewerID: ProfileID,
        session: any SessionProviding
    ) async {
        guard let realtimeHub, let messages else { return }
        guard inboxMessagesTask == nil else { return }
        let conversationIDs = inboxStore.conversations.map(\.id.rawValue)
        guard !conversationIDs.isEmpty else { return }

        inboxMessagesTask = Task { [weak self] in
            guard let self else { return }
            let token = await session.accessToken
            let watch = realtimeHub.watchInboxConversationMessages(
                conversationIDs: conversationIDs,
                accessToken: token,
                debugOwner: "MessagingDomain.inboxDms"
            )
            inboxMessagesRealtimeConsumer = watch.consumer
            for await signal in watch.events {
                guard !Task.isCancelled else { break }
                guard signal.kind == .insert || signal.kind == .update else { continue }
                guard let rawID = signal.conversationID else { continue }
                let conversationID = ConversationID(rawID)
                guard inboxStore.conversations.contains(where: { $0.id == conversationID }) else {
                    continue
                }
                if inboxStore.activeConversationID == conversationID {
#if DEBUG
                    MessagingRealtimeDebugLog.inboxPatchSkipped(
                        reason: "thread_open",
                        conversationID: rawID
                    )
#endif
                    continue
                }
                await applyInboxMessagesRealtimeSignal(
                    signal: signal,
                    conversationID: conversationID,
                    viewerID: viewerID,
                    messages: messages
                )
            }
            inboxMessagesTask = nil
        }
    }

    /// Patch inbox activity from canonical `public.messages` — never denormalized conversation rows.
    private func applyInboxMessagesRealtimeSignal(
        signal: MessageRealtimeSignal,
        conversationID: ConversationID,
        viewerID: ProfileID,
        messages: any MessageRepository
    ) async {
        if let rawMessageID = signal.messageID,
           !MessagingRealtimeDeliveryCoordinator.claimMessageInsert(
               domain: "inbox-dm",
               messageID: rawMessageID,
               conversationID: conversationID.rawValue
           )
        {
            return
        }

        var merged: Message?
        if let payload = signal.recordPayload {
            merged = MessageRealtimeMerge.dmMessage(
                from: payload,
                conversationID: conversationID,
                viewerID: viewerID
            )
        }
        if merged == nil, let rawMessageID = signal.messageID {
#if DEBUG
            MessagingRealtimeDebugLog.networkFallback(reason: "inbox_single_row_hydrate")
#endif
            merged = try? await messages.message(
                id: MessageID(rawMessageID),
                in: conversationID
            )
        }
        guard let newest = merged else { return }

        let policy: MessagesInboxStore.MessagePatchPolicy =
            newest.senderProfileID == viewerID ? .confirmedOutgoing : .canonical
        inboxStore.patchFromMessage(
            newest,
            viewerID: viewerID,
            conversationOpen: false,
            policy: policy,
            source: "inboxRealtime"
        )
#if DEBUG
        MessagingRealtimeDebugLog.messageInsert(
            conversationID: conversationID.rawValue,
            messageID: newest.id.rawValue,
            source: "inboxRealtime"
        )
#endif
    }
}

extension MessagingDomain: ScreenLifecycle, ScreenRealtimeRetaining {}
