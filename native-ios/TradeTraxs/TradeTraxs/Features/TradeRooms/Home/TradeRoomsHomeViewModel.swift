import Foundation
import Observation

/// Trade Rooms home screen owner — presentation over ``MessagingDomain``.
///
/// Initial member-rooms network / room realtime ownership lives in the shared messaging domain
/// (same bootstrap as Messages home).
@Observable
@MainActor
final class TradeRoomsHomeViewModel {
    typealias Phase = MessagingState.Phase

    private(set) var phase: Phase = .idle
    private(set) var viewerID: ProfileID?
    var searchText = ""
    var pendingLeaveRoomID: RoomID?
    var showsLeaveRoomConfirmation = false
    var showsCreateRoom = false

    private let presentCreateOnAppear: Bool
    private var didAutoPresentCreate = false

    private(set) var discoveryMode: TradeRoomDiscoveryMode = .yourRooms
    private(set) var discoveryScope: TradeRoomDiscoveryScope = .all
    private var didApplyInitialDiscoveryMode = false
    private(set) var yourRoomsItems: [ExploreRoomSuggestion] = []
    private(set) var suggestedItems: [ExploreRoomSuggestion] = []
    private(set) var popularItems: [ExploreRoomSuggestion] = []
    private(set) var discoveryPhase: Phase = .idle
    private(set) var discoveryErrorMessage: String?

    private let messages: any MessageRepository
    private let rooms: any RoomRepository
    private let explore: any ExploreRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private let navigationHost: TradeRoomNavigationHost
    private let inboxStore: MessagesInboxStore
    private let realtimeHub: RealtimeHub?
    private let domain: MessagingDomain
    private let joinCoordinator: TradeRoomJoinActionCoordinator

    private var loadTask: Task<Void, Never>?

    init(
        messages: any MessageRepository,
        rooms: any RoomRepository,
        explore: any ExploreRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        navigationHost: TradeRoomNavigationHost = .messages,
        realtimeHub: RealtimeHub? = nil,
        inboxStore: MessagesInboxStore? = nil,
        domain: MessagingDomain? = nil,
        presentCreateOnAppear: Bool = false,
        joinCoordinator: TradeRoomJoinActionCoordinator? = nil
    ) {
        self.messages = messages
        self.rooms = rooms
        self.explore = explore
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.navigationHost = navigationHost
        self.realtimeHub = realtimeHub
        self.inboxStore = inboxStore ?? .shared
        self.domain = domain ?? .shared
        self.presentCreateOnAppear = presentCreateOnAppear
        self.joinCoordinator = joinCoordinator ?? .shared
        self.domain.configure(
            messages: messages,
            rooms: rooms,
            profiles: profiles,
            session: session,
            detailCache: detailCache,
            realtimeHub: realtimeHub
        )
    }

    /// Always derived from the shared inbox store so mark-read / realtime patches refresh badges.
    var items: [TradeRoomInboxItem] {
        buildItems()
    }

    var filteredItems: [TradeRoomInboxItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.room.name.localizedCaseInsensitiveContains(query)
                || ($0.ownerName?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.preview.localizedCaseInsensitiveContains(query)
                || $0.room.slug.localizedCaseInsensitiveContains(query)
        }
    }

    var showsEmpty: Bool {
        phase == .loaded && items.isEmpty
    }

    var showsFilteredEmpty: Bool {
        phase == .loaded && !items.isEmpty && filteredItems.isEmpty
    }

    var joinedRoomIDs: Set<RoomID> {
        Set(items.map(\.id))
    }

    var suggestedDiscoverableRooms: [ExploreRoomSuggestion] {
        filteredDiscoverable(from: suggestedItems, section: "suggested")
    }

    var popularDiscoverableRooms: [ExploreRoomSuggestion] {
        filteredDiscoverable(from: popularItems, section: "popular")
    }

    var discoverableRooms: [ExploreRoomSuggestion] {
        let source = discoveryMode == .popular ? popularItems : suggestedItems
        let filtered = source.filter { !joinedRoomIDs.contains($0.id) }
        #if DEBUG
        RoomDiscoveryProbe.logClientFilter(
            section: discoveryMode.rawValue,
            before: source.count,
            after: filtered.count,
            reason: "alreadyJoinedInInbox"
        )
        #endif
        return filtered
    }

    /// Authoritative Your Rooms rows from home bootstrap RPC (`is_owner` / `is_member`).
    var yourRooms: [ExploreRoomSuggestion] {
        yourRoomsItems
    }

    var displayedDiscoveryRooms: [ExploreRoomSuggestion] {
        switch discoveryMode {
        case .yourRooms:
            return yourRoomsItems
        case .suggested, .popular:
            return discoverableRooms
        }
    }

    var showsDiscoverySection: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasDiscoverableRooms: Bool {
        !items.isEmpty
            || !yourRoomsItems.isEmpty
            || !suggestedDiscoverableRooms.isEmpty
            || !popularDiscoverableRooms.isEmpty
    }

    var showsYourRoomsEmptyState: Bool {
        discoveryMode == .yourRooms && yourRooms.isEmpty && discoveryPhase == .loaded
    }

    /// True once home bootstrap + member rooms load finished — avoids flashing Create before ownership is known.
    var isHeaderOwnershipResolved: Bool {
        discoveryPhase == .loaded && phase != .idle && phase != .loading
    }

    /// Viewer-owned Trade Room from bootstrap RPC (`is_owner`) — at most one.
    var viewerOwnedRoom: ExploreRoomSuggestion? {
        yourRoomsItems.first(where: \.viewerIsOwner)
    }

    func consumePresentCreateIfNeeded() {
        guard presentCreateOnAppear, !didAutoPresentCreate, isHeaderOwnershipResolved else { return }
        didAutoPresentCreate = true
        guard viewerOwnedRoom == nil else { return }
        presentCreateRoom()
    }

    func selectDiscoveryMode(_ mode: TradeRoomDiscoveryMode) {
        guard discoveryMode != mode else { return }
        ExperienceHaptics.play(.selection)
        discoveryMode = mode
        discoveryErrorMessage = nil
        if mode != .yourRooms {
            Task { await loadHomeBootstrap(forceNetwork: true) }
        }
    }

    func browseSuggestedRooms() {
        selectDiscoveryMode(.suggested)
    }

    func selectDiscoveryScope(_ scope: TradeRoomDiscoveryScope) {
        guard discoveryScope != scope else { return }
        ExperienceHaptics.play(.selection)
        discoveryScope = scope
        Task { await loadHomeBootstrap(forceNetwork: true) }
    }

    func openDiscoveryRoom(_ room: ExploreRoomSuggestion) {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(navigationHost.room(room.id))
    }

    func openOwnedRoom() {
        guard let viewerOwnedRoom else { return }
        openDiscoveryRoom(viewerOwnedRoom)
    }

    func joinDiscoveryRoom(_ room: ExploreRoomSuggestion) async {
        guard let viewerID else { return }
        let prior = joinState(for: room.id)
        guard TradeRoomJoinPresentation.isInteractive(prior) else { return }

        let result = await joinCoordinator.performJoinAction(
            room: room,
            viewerID: viewerID,
            rooms: rooms,
            inboxStore: inboxStore,
            onDirectJoinSucceeded: { [weak self] in
                guard let self else { return }
                SessionMemberRoomsStore.shared.invalidate(viewerID: viewerID)
                await self.domain.refreshRooms()
            }
        )

        if result == .joined {
            patchDiscoveryRoomJoined(room.id)
            SessionTradeRoomsDiscoveryStore.shared.invalidate(viewerID: viewerID)
            await loadHomeBootstrap(forceNetwork: true)
        } else if result == .requested {
            patchDiscoveryRoomRequested(room.id)
        }

        if let message = joinCoordinator.lastErrorMessage {
            discoveryErrorMessage = message
        }
    }

    func retryDiscovery() {
        Task { await loadHomeBootstrap(forceNetwork: true) }
    }

    func joinState(for roomID: RoomID) -> TradeRoomDiscoveryJoinState {
        if joinedRoomIDs.contains(roomID) { return .joined }
        let pool = yourRoomsItems + suggestedItems + popularItems
        guard let room = pool.first(where: { $0.id == roomID }) else {
            return joinCoordinator.mutationStates[roomID] ?? .idle
        }
        return joinCoordinator.effectiveState(
            for: room,
            isJoined: false
        )
    }

    /// Authoritative ownership from Trade Rooms RPC — never inferred client-side.
    func isViewerOwner(of room: ExploreRoomSuggestion) -> Bool {
        room.viewerIsOwner
    }

    private func patchDiscoveryRoomJoined(_ roomID: RoomID) {
        patchDiscoverableCollections(roomID: roomID) { room in
            var updated = room
            updated.isJoined = true
            updated.isMember = true
            updated.viewerJoinRequestState = nil
            return updated
        }
    }

    private func patchDiscoveryRoomRequested(_ roomID: RoomID) {
        patchDiscoverableCollections(roomID: roomID) { room in
            var updated = room
            updated.viewerJoinRequestState = .pending
            return updated
        }
    }

    func applyRoomMetadata(_ room: TradeRoom) {
        patchAllDiscoveryCollections(roomID: room.id) { suggestion in
            var updated = suggestion
            updated.applyMetadata(from: room)
            return updated
        }
    }

    private func patchDiscoverableCollections(
        roomID: RoomID,
        transform: (ExploreRoomSuggestion) -> ExploreRoomSuggestion
    ) {
        if let index = suggestedItems.firstIndex(where: { $0.id == roomID }) {
            suggestedItems[index] = transform(suggestedItems[index])
        }
        if let index = popularItems.firstIndex(where: { $0.id == roomID }) {
            popularItems[index] = transform(popularItems[index])
        }
    }

    private func patchAllDiscoveryCollections(
        roomID: RoomID,
        transform: (ExploreRoomSuggestion) -> ExploreRoomSuggestion
    ) {
        if let index = yourRoomsItems.firstIndex(where: { $0.id == roomID }) {
            yourRoomsItems[index] = transform(yourRoomsItems[index])
        }
        patchDiscoverableCollections(roomID: roomID, transform: transform)
    }

    func loadIfNeeded() {
        guard loadTask == nil, phase != .loaded else { return }
        loadTask = Task { await performLoad(forceNetwork: false) }
    }

    func refresh() async {
        await performLoad(forceNetwork: true)
    }

    func releaseRealtime() {
        domain.releaseRealtime()
    }

    func openRoom(_ item: TradeRoomInboxItem) {
        ExperienceHaptics.play(.selection)
        // Mark-read runs inside ``NavigationCoordinator`` for `.messages(.room)`.
        navigationCoordinator.open(navigationHost.room(item.id))
    }

    func presentCreateRoom() {
        ExperienceHaptics.play(.selection)
        showsCreateRoom = true
    }

    func handleRoomCreated(_ room: TradeRoom) {
        showsCreateRoom = false
        Task {
            if let viewerID {
                SessionTradeRoomsDiscoveryStore.shared.invalidate(viewerID: viewerID)
            }
            await domain.refreshRooms()
            await loadHomeBootstrap(forceNetwork: true)
            didApplyInitialDiscoveryMode = false
            applyInitialDiscoveryModeIfNeeded()
            discoveryMode = .yourRooms
            openRoom(
                TradeRoomInboxItem(
                    room: room,
                    ownerName: nil,
                    ownerIsVerified: false,
                    preview: room.description ?? "No messages yet",
                    timestamp: inboxStore.roomActivityAt[room.id],
                    unreadCount: 0,
                    isMuted: false
                )
            )
        }
    }

    func toggleMute(roomID: RoomID) {
        ExperienceHaptics.play(.selection)
        inboxStore.toggleMute(roomID: roomID)
    }

    func isRoomMuted(_ roomID: RoomID) -> Bool {
        inboxStore.isRoomMuted(roomID)
    }

    func requestLeaveRoom(id: RoomID) {
        ExperienceHaptics.play(.warning)
        pendingLeaveRoomID = id
        showsLeaveRoomConfirmation = true
    }

    func cancelLeaveRoom() {
        pendingLeaveRoomID = nil
        showsLeaveRoomConfirmation = false
    }

    func confirmLeaveRoom() async {
        guard let id = pendingLeaveRoomID else { return }
        pendingLeaveRoomID = nil
        showsLeaveRoomConfirmation = false
        await leaveRoom(id: id)
    }

    func leaveRoom(id: RoomID) async {
        ExperienceHaptics.play(.warning)
        guard let viewerID else {
            inboxStore.removeRoom(id: id)
            return
        }
        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || id.rawValue.hasPrefix("dev-") {
            inboxStore.removeRoom(id: id)
            return
        }
        do {
            try await rooms.leave(roomID: id, profileID: viewerID)
            inboxStore.removeRoom(id: id)
            SessionTradeRoomsDiscoveryStore.shared.invalidate(viewerID: viewerID)
            yourRoomsItems.removeAll { $0.id == id }
            await loadHomeBootstrap(forceNetwork: true)
            ExperienceHaptics.play(.success)
        } catch {
            ExperienceHaptics.play(.warning)
        }
    }

    private func performLoad(forceNetwork: Bool) async {
        if phase != .loaded {
            phase = .loading
        }
        async let roomsLoad: Void = {
            if forceNetwork {
                await domain.refreshRooms()
            } else {
                await domain.bootstrapRoomsIfNeeded(forceNetwork: false)
            }
        }()
        async let bootstrapLoad: Void = loadHomeBootstrap(forceNetwork: forceNetwork)
        _ = await (roomsLoad, bootstrapLoad)

        if viewerID == nil {
            viewerID = domain.state.viewerID
        }
        phase = domain.state.phase
        applyInitialDiscoveryModeIfNeeded()
        reconcileYourRoomsWithMembership()
        logDisplayedRooms()
        await domain.retainRealtime()
        loadTask = nil
    }

    private func applyInitialDiscoveryModeIfNeeded() {
        guard !didApplyInitialDiscoveryMode else { return }
        didApplyInitialDiscoveryMode = true
        if items.isEmpty, yourRoomsItems.isEmpty {
            discoveryMode = .suggested
        } else {
            discoveryMode = .yourRooms
        }
        #if DEBUG
        TradeRoomsHomeBootstrapProbe.initialCategory(discoveryMode)
        #endif
    }

    private func filteredDiscoverable(
        from source: [ExploreRoomSuggestion],
        section: String
    ) -> [ExploreRoomSuggestion] {
        let filtered = source.filter { !joinedRoomIDs.contains($0.id) }
        #if DEBUG
        RoomDiscoveryProbe.logClientFilter(
            section: section,
            before: source.count,
            after: filtered.count,
            reason: "alreadyJoinedInInbox"
        )
        #endif
        return filtered
    }

    private func loadHomeBootstrap(forceNetwork: Bool) async {
        let sessionViewer = await session.currentUserID.map { ProfileID($0.rawValue) }
        guard let sessionViewer else {
            discoveryPhase = .loaded
            return
        }
        viewerID = sessionViewer

        if !forceNetwork,
           discoveryPhase == .loaded,
           !yourRoomsItems.isEmpty || !suggestedItems.isEmpty || !popularItems.isEmpty
        {
            return
        }

        if DemoExperienceSupport.usesLocalBundledSocialData(sessionViewer) {
            let bootstrap: TradeRoomsHomeBootstrap
            if inboxStore.rooms.isEmpty {
                bootstrap = TradeRoomsHomeBootstrap(
                    viewerID: sessionViewer,
                    scope: discoveryScope,
                    yourRooms: [],
                    suggested: [],
                    popular: []
                )
            } else {
                let bootstrapScope = discoveryScope.bootstrapCacheScope
                bootstrap = (try? await explore.tradeRoomsHomeBootstrap(scope: bootstrapScope, limit: 20))
                    ?? TradeRoomsFixtures.homeBootstrap(viewerID: sessionViewer, scope: bootstrapScope)
            }
            SessionTradeRoomsDiscoveryStore.shared.seed(bootstrap, for: sessionViewer)
            applyHomeBootstrap(bootstrap, viewerID: sessionViewer)
            discoveryPhase = .loaded
            #if DEBUG
            TradeRoomsHomeBootstrapProbe.bootstrapReturned(bootstrap)
            #endif
            return
        }

        if yourRoomsItems.isEmpty, suggestedItems.isEmpty, popularItems.isEmpty {
            discoveryPhase = .loading
        }
        discoveryErrorMessage = nil

        do {
            let cacheScope = discoveryScope.bootstrapCacheScope
            let bootstrap = try await SessionTradeRoomsDiscoveryStore.shared.coalesce(
                viewerID: sessionViewer,
                scope: cacheScope,
                forceNetwork: forceNetwork
            ) { [explore, cacheScope] in
                try await explore.tradeRoomsHomeBootstrap(scope: cacheScope, limit: 20)
            }
            applyHomeBootstrap(bootstrap, viewerID: sessionViewer)
            discoveryPhase = .loaded
            #if DEBUG
            TradeRoomsHomeBootstrapProbe.bootstrapReturned(bootstrap)
            #endif
        } catch {
            discoveryPhase = .loaded
            discoveryErrorMessage = ProfileSectionSupport.message(for: error)
        }
    }

    private func applyHomeBootstrap(_ bootstrap: TradeRoomsHomeBootstrap, viewerID: ProfileID) {
        if let bootstrapViewer = bootstrap.viewerID {
            self.viewerID = bootstrapViewer
        } else {
            self.viewerID = viewerID
        }
        yourRoomsItems = bootstrap.yourRooms
        suggestedItems = bootstrap.suggested
        popularItems = bootstrap.popular
        reconcileYourRoomsWithMembership()
        logDisplayedRooms()
    }

    /// Web sidebar parity — inbox member rooms must appear in Your Rooms even when
    /// bootstrap RPC omits private/non-profile rooms.
    private func reconcileYourRoomsWithMembership() {
        guard let viewerID else { return }
        var merged = yourRoomsItems
        var ids = Set(merged.map(\.id))
        for item in items {
            guard !ids.contains(item.id) else { continue }
            let suggestion = ExploreRoomSuggestion.fromMembership(
                room: item.room,
                ownerName: item.ownerName,
                ownerUsername: nil,
                viewerID: viewerID,
                isOwner: item.room.ownerProfileID == viewerID,
                isMember: true
            )
            merged.append(suggestion)
            ids.insert(item.id)
            RoomDiscoveryProbe.logMergedFromMembership(roomID: item.id)
        }
        merged.sort { lhs, rhs in
            if lhs.viewerIsOwner != rhs.viewerIsOwner { return lhs.viewerIsOwner }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        yourRoomsItems = merged
    }

    private func logDisplayedRooms() {
        RoomDiscoveryProbe.logDisplayed(
            memberCards: showsDiscoverySection ? items.count : filteredItems.count,
            discoveryRows: displayedDiscoveryRooms.count,
            mode: discoveryMode.rawValue
        )
    }

    private func buildItems() -> [TradeRoomInboxItem] {
        inboxStore.rooms.map { room in
            let owner = domain.profile(id: room.ownerProfileID) ?? detailCache.profile(id: room.ownerProfileID)
            return TradeRoomInboxItem(
                room: room,
                ownerName: owner?.displayName,
                ownerIsVerified: owner?.isCreator == true,
                preview: inboxStore.roomPreviews[room.id] ?? room.description ?? "No messages yet",
                timestamp: inboxStore.roomActivityAt[room.id],
                unreadCount: inboxStore.roomUnread[room.id] ?? 0,
                isMuted: inboxStore.isRoomMuted(room.id)
            )
        }
        .sorted { lhs, rhs in
            let lu = lhs.unreadCount > 0
            let ru = rhs.unreadCount > 0
            if lu != ru { return lu && !ru }
            return lhs.room.name.localizedCaseInsensitiveCompare(rhs.room.name) == .orderedAscending
        }
    }
}

/// Canonical screen name for Trade Rooms home.
typealias TradeRoomsScreenViewModel = TradeRoomsHomeViewModel

/// Room conversation thread — pagination / composer remain thread-scoped.
typealias RoomConversationScreenViewModel = RoomConversationViewModel
