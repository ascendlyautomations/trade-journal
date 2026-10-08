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

    private var presentCreateOnAppear: Bool
    private var didAutoPresentCreate = false

    private(set) var discoveryMode: TradeRoomDiscoveryMode = .yourRooms
    private(set) var discoveryScope: TradeRoomDiscoveryScope = .all
    /// Set when the user taps a scope chip. Later loads must not move the chip.
    private var didUserSelectDiscoveryScope = false
    /// Set once membership cache or the first home load can choose the opening chip.
    private var didLatchInitialDiscoveryScope = false
    private var didApplyInitialDiscoveryMode = false
    private(set) var yourRoomsItems: [ExploreRoomSuggestion] = []
    private(set) var suggestedItems: [ExploreRoomSuggestion] = []
    private(set) var popularItems: [ExploreRoomSuggestion] = []
    private(set) var discoveryPhase: Phase = .idle
    private(set) var discoveryErrorMessage: String?
    private(set) var isLoadingMoreDiscovery = false

    private static let discoveryInitialLimit = 20

    private static func nonEmptyCursor(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
    private var suggestedNextCursor: String?
    private var popularNextCursor: String?

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
    /// Hosting tab selected (Home / Feed / Profile). Narrow guard for home discovery RPC only.
    private var isHostingTabActive = true

#if DEBUG
    private let lifecycleProbeID = String(UUID().uuidString.prefix(8))
#endif

    private struct BootstrapFingerprint: Equatable {
        var your: [RoomID]
        var suggested: [RoomID]
        var popular: [RoomID]
    }

    private struct DisplayedSnapshot: Equatable {
        var mode: String
        var memberCards: Int
        var discoveryRowIDs: [RoomID]
    }

    private var lastAppliedBootstrapFingerprint: BootstrapFingerprint?
    private var lastLoggedDisplayedSnapshot: DisplayedSnapshot?

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
        if viewerID == nil {
            viewerID = self.inboxStore.persistedViewerID ?? self.domain.state.viewerID
        }
        restoreCachedHomeBootstrap()
        hydrateYourRoomsFromMembershipCache()
        latchInitialDiscoveryScopeIfNeeded()
        self.domain.configure(
            messages: messages,
            rooms: rooms,
            profiles: profiles,
            session: session,
            detailCache: detailCache,
            realtimeHub: realtimeHub
        )
#if DEBUG
        TradeRoomsHomeLifecycleProbe.viewModelInit(id: lifecycleProbeID)
#endif
    }

    deinit {
#if DEBUG
        TradeRoomsHomeLifecycleProbe.viewModelDeinit(id: lifecycleProbeID)
#endif
    }

    func setHostingTabActive(_ active: Bool) {
        isHostingTabActive = active
#if DEBUG
        TradeRoomsHomeLifecycleProbe.hostingTabActive(id: lifecycleProbeID, active: active)
#endif
    }

    func noteViewAppeared() {
#if DEBUG
        TradeRoomsHomeLifecycleProbe.viewAppear(id: lifecycleProbeID)
#endif
    }

    func noteViewDisappeared() {
#if DEBUG
        TradeRoomsHomeLifecycleProbe.viewDisappear(id: lifecycleProbeID)
#endif
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

    /// Chip on screen. Members open on Your Rooms from cache before the user picks a chip.
    var activeDiscoveryScope: TradeRoomDiscoveryScope {
        if didUserSelectDiscoveryScope || didLatchInitialDiscoveryScope {
            return discoveryScope
        }
        if hasCachedJoinedRoom {
            return .yourRooms
        }
        return discoveryScope
    }

    var joinedRoomIDs: Set<RoomID> {
        Set(items.map(\.id))
    }

    var suggestedDiscoverableRooms: [ExploreRoomSuggestion] {
        sortedForAllScopeIfNeeded(
            filteredDiscoverable(from: suggestedItems, section: "suggested")
        )
    }

    var popularDiscoverableRooms: [ExploreRoomSuggestion] {
        sortedForAllScopeIfNeeded(
            filteredDiscoverable(from: popularItems, section: "popular")
        )
    }

    var canLoadMoreAllScopeDiscovery: Bool {
        activeDiscoveryScope == .all
            && !isLoadingMoreDiscovery
            && (suggestedNextCursor != nil || popularNextCursor != nil)
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

    func armPresentCreateOnAppear() {
        presentCreateOnAppear = true
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
        didUserSelectDiscoveryScope = true
        didLatchInitialDiscoveryScope = true
        guard discoveryScope != scope else { return }
        ExperienceHaptics.play(.selection)
        discoveryScope = scope
        suggestedNextCursor = nil
        popularNextCursor = nil
        Task { await loadHomeBootstrap(forceNetwork: true) }
    }

    func loadMoreAllScopeDiscoveryIfNeeded(currentRoomID: RoomID) async {
        guard activeDiscoveryScope == .all else { return }
        guard !isLoadingMoreDiscovery else { return }
        if let last = suggestedDiscoverableRooms.last?.id,
           last == currentRoomID,
           suggestedNextCursor != nil
        {
            await loadMoreDiscoveryPage(section: .suggested)
            return
        }
        if let last = popularDiscoverableRooms.last?.id,
           last == currentRoomID,
           popularNextCursor != nil
        {
            await loadMoreDiscoveryPage(section: .popular)
        }
    }

    private func loadMoreDiscoveryPage(section: TradeRoomDiscoveryMode) async {
        guard section == .suggested || section == .popular else { return }
        guard let viewerID else { return }
        isLoadingMoreDiscovery = true
        defer { isLoadingMoreDiscovery = false }
        do {
            let bootstrap = try await explore.tradeRoomsHomeBootstrap(
                scope: .all,
                limit: Self.discoveryInitialLimit,
                suggestedCursor: section == .suggested ? suggestedNextCursor : nil,
                popularCursor: section == .popular ? popularNextCursor : nil
            )
            if section == .suggested {
                suggestedItems = mergeDiscoveryRows(existing: suggestedItems, incoming: bootstrap.suggested)
                suggestedNextCursor = Self.nonEmptyCursor(bootstrap.suggestedNextCursor)
            } else {
                popularItems = mergeDiscoveryRows(existing: popularItems, incoming: bootstrap.popular)
                popularNextCursor = Self.nonEmptyCursor(bootstrap.popularNextCursor)
            }
            _ = reconcileYourRoomsWithMembership()
            logDisplayedIfChanged(source: .network)
            _ = viewerID
        } catch {
            discoveryErrorMessage = ProfileSectionSupport.message(for: error)
        }
    }

    private func mergeDiscoveryRows(
        existing: [ExploreRoomSuggestion],
        incoming: [ExploreRoomSuggestion]
    ) -> [ExploreRoomSuggestion] {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for row in incoming where !seen.contains(row.id) {
            merged.append(row)
            seen.insert(row.id)
        }
        for row in incoming {
            if let index = merged.firstIndex(where: { $0.id == row.id }) {
                merged[index] = row
            }
        }
        return merged
    }

    private func applyDiscoveryPagination(from bootstrap: TradeRoomsHomeBootstrap) {
        if let next = bootstrap.suggestedNextCursor, !next.isEmpty {
            suggestedNextCursor = next
        } else {
            suggestedNextCursor = nil
        }
        if let next = bootstrap.popularNextCursor, !next.isEmpty {
            popularNextCursor = next
        } else {
            popularNextCursor = nil
        }
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
        suggestedNextCursor = nil
        popularNextCursor = nil
        await performLoad(forceNetwork: true)
    }

    func releaseRealtime() {
#if DEBUG
        TradeRoomsHomeLifecycleProbe.realtime(id: lifecycleProbeID, event: "release")
#endif
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
            didUserSelectDiscoveryScope = true
            didLatchInitialDiscoveryScope = true
            discoveryScope = .yourRooms
            discoveryMode = .yourRooms
            openRoom(
                TradeRoomInboxItem(
                    room: room,
                    ownerName: nil,
                    ownerIsVerified: TradeTraxsOfficialAccountPolicy.showsTradeTraxsIdentityBadge(
                        owner: nil,
                        ownerProfileID: room.ownerProfileID
                    ),
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
#if DEBUG
        TradeRoomsHomeLifecycleProbe.performLoad(
            id: lifecycleProbeID,
            phase: String(describing: phase),
            forceNetwork: forceNetwork,
            event: "begin"
        )
#endif
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
        _ = reconcileYourRoomsWithMembership()
        latchInitialDiscoveryScopeIfNeeded()
        phase = domain.state.phase
        applyInitialDiscoveryModeIfNeeded()
        logDisplayedIfChanged(
            source: forceNetwork ? .refresh : .cache
        )
#if DEBUG
        TradeRoomsHomeLifecycleProbe.realtime(id: lifecycleProbeID, event: "retain")
#endif
        await domain.retainRealtime()
        loadTask = nil
#if DEBUG
        TradeRoomsHomeLifecycleProbe.performLoad(
            id: lifecycleProbeID,
            phase: String(describing: phase),
            forceNetwork: forceNetwork,
            event: "end"
        )
#endif
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

    /// Last row in the All-scope discovery scroll (Suggested, then Popular).
    private var allScopeDiscoveryPaginationAnchorRoomID: RoomID? {
        if !popularDiscoverableRooms.isEmpty {
            return popularDiscoverableRooms.last?.id
        }
        return suggestedDiscoverableRooms.last?.id
    }

    private func sortedForAllScopeIfNeeded(_ rooms: [ExploreRoomSuggestion]) -> [ExploreRoomSuggestion] {
        guard activeDiscoveryScope == .all else { return rooms }
        return TradeRoomDiscoveryMemberCountSort.sorted(rooms)
    }

    private func bootstrapFetchLimit(for scope: TradeRoomDiscoveryScope) -> Int {
        _ = scope
        return Self.discoveryInitialLimit
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
#if DEBUG
        TradeRoomsHomeLifecycleProbe.loadHomeBootstrap(
            id: lifecycleProbeID,
            event: "begin",
            hostingTabActive: isHostingTabActive,
            forceNetwork: forceNetwork
        )
#endif
        guard isHostingTabActive else {
#if DEBUG
            TradeRoomsHomeLifecycleProbe.loadHomeBootstrap(
                id: lifecycleProbeID,
                event: "skip-inactive-tab",
                hostingTabActive: false,
                forceNetwork: forceNetwork
            )
#endif
            return
        }

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
            let bootstrapScope = discoveryScope.bootstrapCacheScope
            let bootstrap: TradeRoomsHomeBootstrap
            if sessionViewer == DemoExperienceSupport.profileID {
                bootstrap = DemoExploreTradeRoom.homeBootstrap(
                    viewerID: sessionViewer,
                    scope: bootstrapScope
                )
            } else {
                bootstrap = TradeRoomsFixtures.homeBootstrap(
                    viewerID: sessionViewer,
                    scope: bootstrapScope
                )
            }
            SessionTradeRoomsDiscoveryStore.shared.seed(bootstrap, for: sessionViewer)
            applyHomeBootstrap(bootstrap, viewerID: sessionViewer, source: .cache)
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
            let hadFreshCache = !forceNetwork
                && SessionTradeRoomsDiscoveryStore.shared.cached(for: sessionViewer, scope: cacheScope) != nil
            let bootstrapSource: RoomDiscoveryProbe.DisplayedSource = forceNetwork
                ? .refresh
                : (hadFreshCache ? .cache : .network)
            let fetchLimit = bootstrapFetchLimit(for: cacheScope)
            let bootstrap = try await SessionTradeRoomsDiscoveryStore.shared.coalesce(
                viewerID: sessionViewer,
                scope: cacheScope,
                forceNetwork: forceNetwork
            ) { [explore, cacheScope, fetchLimit] in
                try await explore.tradeRoomsHomeBootstrap(
                    scope: cacheScope,
                    limit: fetchLimit
                )
            }
            guard isHostingTabActive else {
#if DEBUG
                TradeRoomsHomeLifecycleProbe.loadHomeBootstrap(
                    id: lifecycleProbeID,
                    event: "cancel-after-fetch-inactive-tab",
                    hostingTabActive: false,
                    forceNetwork: forceNetwork
                )
#endif
                return
            }
            applyHomeBootstrap(bootstrap, viewerID: sessionViewer, source: bootstrapSource)
            discoveryPhase = .loaded
            #if DEBUG
            TradeRoomsHomeBootstrapProbe.bootstrapReturned(bootstrap)
            TradeRoomsHomeLifecycleProbe.loadHomeBootstrap(
                id: lifecycleProbeID,
                event: "end",
                hostingTabActive: isHostingTabActive,
                forceNetwork: forceNetwork
            )
            #endif
        } catch {
            discoveryPhase = .loaded
            discoveryErrorMessage = ProfileSectionSupport.message(for: error)
        }
    }

    private func applyHomeBootstrap(
        _ bootstrap: TradeRoomsHomeBootstrap,
        viewerID: ProfileID,
        source: RoomDiscoveryProbe.DisplayedSource
    ) {
        if let bootstrapViewer = bootstrap.viewerID {
            self.viewerID = bootstrapViewer
        } else {
            self.viewerID = viewerID
        }

        let fingerprint = BootstrapFingerprint(
            your: bootstrap.yourRooms.map(\.id),
            suggested: bootstrap.suggested.map(\.id),
            popular: bootstrap.popular.map(\.id)
        )
        let bootstrapChanged = fingerprint != lastAppliedBootstrapFingerprint
        if bootstrapChanged {
            lastAppliedBootstrapFingerprint = fingerprint
            yourRoomsItems = bootstrap.yourRooms
            suggestedItems = bootstrap.suggested
            popularItems = bootstrap.popular
            applyDiscoveryPagination(from: bootstrap)
        }

        _ = reconcileYourRoomsWithMembership()
        if bootstrapChanged {
            logDisplayedIfChanged(source: source)
        }
    }

    private func restoreCachedHomeBootstrap() {
        guard let viewerID else { return }
        guard yourRoomsItems.isEmpty, suggestedItems.isEmpty, popularItems.isEmpty else { return }
        guard let bootstrap = SessionTradeRoomsDiscoveryStore.shared.cached(for: viewerID, scope: .all) else {
            return
        }
        applyHomeBootstrap(bootstrap, viewerID: viewerID, source: .cache)
        discoveryPhase = .loaded
    }

    /// Fills Your Rooms from the member-room cache when the inbox list is not in memory yet.
    private func hydrateYourRoomsFromMembershipCache() {
        guard let viewerID, inboxStore.rooms.isEmpty, yourRoomsItems.isEmpty else { return }
        guard let cached = SessionMemberRoomsStore.shared.cached(for: viewerID), !cached.0.isEmpty else {
            return
        }
        yourRoomsItems = cached.0.map { room in
            ExploreRoomSuggestion.fromMembership(
                room: room,
                ownerName: nil,
                ownerUsername: nil,
                viewerID: viewerID,
                isOwner: room.ownerProfileID == viewerID,
                isMember: true
            )
        }
    }

    private var hasCachedJoinedRoom: Bool {
        if !inboxStore.rooms.isEmpty || !yourRoomsItems.isEmpty {
            return true
        }
        let viewer = viewerID ?? inboxStore.persistedViewerID ?? domain.state.viewerID
        guard let viewer else { return false }
        if let cached = SessionMemberRoomsStore.shared.cached(for: viewer), !cached.0.isEmpty {
            return true
        }
        if let bootstrap = SessionTradeRoomsDiscoveryStore.shared.cached(for: viewer, scope: .all),
           !bootstrap.yourRooms.isEmpty {
            return true
        }
        return false
    }

    private var membershipResolvedEmpty: Bool {
        inboxStore.hasLoadedRooms
            && inboxStore.rooms.isEmpty
            && discoveryPhase == .loaded
            && yourRoomsItems.isEmpty
    }

    /// Opening chip only. A later manual chip change sets ``didUserSelectDiscoveryScope``.
    private func latchInitialDiscoveryScopeIfNeeded() {
        guard !didUserSelectDiscoveryScope, !didLatchInitialDiscoveryScope else { return }
        if hasCachedJoinedRoom {
            didLatchInitialDiscoveryScope = true
            discoveryScope = .yourRooms
        } else if membershipResolvedEmpty {
            didLatchInitialDiscoveryScope = true
            discoveryScope = .all
        }
    }

    /// Web sidebar parity — inbox member rooms must appear in Your Rooms even when
    /// bootstrap RPC omits private/non-profile rooms.
    @discardableResult
    private func reconcileYourRoomsWithMembership() -> Bool {
        let beforeIDs = yourRoomsItems.map(\.id)
        let resolvedViewer = viewerID
        var merged = yourRoomsItems
        var ids = Set(merged.map(\.id))
        for item in items {
            guard !ids.contains(item.id) else { continue }
            let suggestion = ExploreRoomSuggestion.fromMembership(
                room: item.room,
                ownerName: item.ownerName,
                ownerUsername: nil,
                viewerID: resolvedViewer,
                isOwner: resolvedViewer.map { item.room.ownerProfileID == $0 } ?? false,
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
        return beforeIDs != merged.map(\.id)
    }

    private func currentDisplayedSnapshot() -> DisplayedSnapshot {
        DisplayedSnapshot(
            mode: discoveryMode.rawValue,
            memberCards: showsDiscoverySection ? items.count : filteredItems.count,
            discoveryRowIDs: displayedDiscoveryRooms.map(\.id)
        )
    }

    private func logDisplayedIfChanged(source: RoomDiscoveryProbe.DisplayedSource) {
        let snapshot = currentDisplayedSnapshot()
        guard snapshot != lastLoggedDisplayedSnapshot else { return }
        lastLoggedDisplayedSnapshot = snapshot
        RoomDiscoveryProbe.logDisplayed(
            memberCards: snapshot.memberCards,
            discoveryRows: snapshot.discoveryRowIDs.count,
            mode: snapshot.mode,
            source: source
        )
    }

    private func buildItems() -> [TradeRoomInboxItem] {
        inboxStore.rooms.map { room in
            let owner: Profile? = {
                if !ProfileIDQueryPolicy.isQueryable(room.ownerProfileID) {
                    return TradeRoomOfficialOwnerPresentation.systemOwnerProfile(roomID: room.id)
                }
                return domain.profile(id: room.ownerProfileID) ?? detailCache.profile(id: room.ownerProfileID)
            }()
            return TradeRoomInboxItem(
                room: room,
                ownerName: owner?.displayName,
                ownerIsVerified: TradeTraxsOfficialAccountPolicy.showsTradeTraxsIdentityBadge(
                    owner: owner,
                    ownerProfileID: room.ownerProfileID
                ),
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
