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
    private(set) var searchDiscoveryRooms: [ExploreRoomSuggestion] = []
    private(set) var searchDiscoveryPhase: Phase = .idle

    private static let discoveryInitialLimit = 20
    private static let allScopeDiscoveryPageSize = 8
    private static let searchDiscoveryLimit = 20
    private static let searchDebounceNanoseconds: UInt64 = 280_000_000

    private static func nonEmptyCursor(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
    private var suggestedNextCursor: String?
    private var popularNextCursor: String?
    private var allScopeVisibleCount = allScopeDiscoveryPageSize

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
    private var searchTask: Task<Void, Never>?
    private var searchGeneration: UInt64 = 0
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
        syncOwnedTradeRoomPresentationFromLocalStores()
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
        normalizeDiscoveryScopeIfNeeded()
        syncOwnedTradeRoomPresentationFromLocalStores()
        Task { await refreshOwnedTradeRoomHeaderIfNeeded() }
#if DEBUG
        TradeRoomsHomeLifecycleProbe.viewAppear(id: lifecycleProbeID)
#endif
    }

    private func normalizeDiscoveryScopeIfNeeded() {
        let normalized = TradeRoomDiscoveryScope.normalizedHomeScope(discoveryScope)
        if normalized != discoveryScope {
            discoveryScope = normalized
        }
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
        guard phase == .loaded else { return false }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        if searchDiscoveryPhase == .loading { return false }
        return filteredItems.isEmpty && searchDiscoveryDisplayRooms.isEmpty
    }

    /// Public discovery hits while searching — excludes joined rooms already shown as inbox cards.
    var searchDiscoveryDisplayRooms: [ExploreRoomSuggestion] {
        let inboxIDs = Set(filteredItems.map(\.id))
        return searchDiscoveryRooms.filter { !inboxIDs.contains($0.id) }
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
        var ids = Set(items.map(\.id))
        ids.formUnion(TradeRoomMembershipStore.shared.allJoinedRoomIDs)
        return ids
    }

    var suggestedDiscoverableRooms: [ExploreRoomSuggestion] {
        filteredDiscoverable(from: suggestedItems, section: "suggested")
    }

    var popularDiscoverableRooms: [ExploreRoomSuggestion] {
        filteredDiscoverable(from: popularItems, section: "popular")
    }

    /// All tab — server `popular` keyset (member count desc), excluding joined and viewer-owned rooms.
    var allScopeDiscoverableRooms: [ExploreRoomSuggestion] {
        filteredDiscoverable(
            from: popularItems,
            section: "popular_all",
            excludeViewerOwnedRoom: true
        )
    }

    var allScopeDisplayedDiscoverableRooms: [ExploreRoomSuggestion] {
        Array(allScopeDiscoverableRooms.prefix(allScopeVisibleCount))
    }

    var showsAllScopeShowMore: Bool {
        guard activeDiscoveryScope == .all else { return false }
        guard !allScopeDiscoverableRooms.isEmpty else { return false }
        if allScopeVisibleCount < allScopeDiscoverableRooms.count { return true }
        return popularNextCursor != nil
    }

    /// Official or Popular tab — one list (Popular preserves RPC member-count order).
    var unifiedDiscoverableRooms: [ExploreRoomSuggestion] {
        switch activeDiscoveryScope {
        case .popular:
            return filteredDiscoverable(from: popularItems, section: "popular")
        case .official:
            return filteredDiscoverable(from: popularItems, section: "popular")
        default:
            return []
        }
    }

    var canLoadMoreAllScopeDiscovery: Bool {
        showsAllScopeShowMore
    }

    var canLoadMoreUnifiedDiscovery: Bool {
        activeDiscoveryScope.showsUnifiedDiscoveryList
            && !isLoadingMoreDiscovery
            && popularNextCursor != nil
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

    /// Joined tab — viewer-owned room pinned first; includes cached ownership before bootstrap catches up.
    var yourRooms: [ExploreRoomSuggestion] {
        joinedDiscoveryRoomsOrdered()
    }

    var favoriteRooms: [ExploreRoomSuggestion] {
        yourRoomsItems.filter {
            TradeRoomFavoritesStore.shared.isFavorited($0.id) || $0.viewerIsFavorited
        }
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
            || !allScopeDiscoverableRooms.isEmpty
    }

    var showsYourRoomsEmptyState: Bool {
        discoveryMode == .yourRooms && yourRooms.isEmpty && discoveryPhase == .loaded
    }

    /// True once we can show Create vs owned-room avatar (cache or loaded bootstrap).
    var isHeaderOwnershipResolved: Bool {
        if viewerOwnedRoom != nil { return true }
        if let viewerID, detailCache.ownedTradeRoom(for: viewerID) != nil { return true }
        if let viewerID, detailCache.hasResolvedOwnedTradeRoom(for: viewerID),
           inboxStore.hasLoadedRooms
        {
            return true
        }
        return discoveryPhase == .loaded && phase != .idle && phase != .loading
    }

    /// Viewer-owned Trade Room — inbox owner row first, then bootstrap/cache/intent.
    var viewerOwnedRoom: ExploreRoomSuggestion? {
        guard let viewerID else { return nil }
        if let item = items.first(where: { $0.room.ownerProfileID == viewerID }) {
            return ownedRoomSuggestion(from: item.room)
        }
        if let room = detailCache.ownedTradeRoom(for: viewerID) {
            return ownedRoomSuggestion(from: room)
        }
        if let owned = yourRoomsItems.first(where: \.viewerIsOwner) {
            return owned
        }
        if let cached = SessionMemberRoomsStore.shared.cached(for: viewerID)?.0,
           let room = cached.first(where: { $0.ownerProfileID == viewerID })
        {
            return ownedRoomSuggestion(from: room)
        }
        if let created = TradeRoomCreationIntent.shared.createdRoomForProfile,
           created.ownerProfileID == viewerID
        {
            return ownedRoomSuggestion(from: created)
        }
        return nil
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
        let scope = TradeRoomDiscoveryScope.normalizedHomeScope(scope)
        didUserSelectDiscoveryScope = true
        didLatchInitialDiscoveryScope = true
        guard discoveryScope != scope else { return }
        ExperienceHaptics.play(.selection)
        discoveryScope = scope
        suggestedNextCursor = nil
        popularNextCursor = nil
        if scope == .all {
            allScopeVisibleCount = Self.allScopeDiscoveryPageSize
        }
        Task { await loadHomeBootstrap(forceNetwork: true) }
    }

    func showMoreAllScopeDiscovery() {
        guard activeDiscoveryScope == .all else { return }
        ExperienceHaptics.play(.selection)
        allScopeVisibleCount += Self.allScopeDiscoveryPageSize
        Task { await ensureAllScopeDiscoveryLoadedThroughVisibleWindow() }
    }

    func loadMoreAllScopeDiscoveryIfNeeded(currentRoomID: RoomID) async {
        await loadMoreDiscoveryIfNeeded(currentRoomID: currentRoomID)
    }

    private func ensureAllScopeDiscoveryLoadedThroughVisibleWindow() async {
        guard activeDiscoveryScope == .all else { return }
        while allScopeDiscoverableRooms.count < allScopeVisibleCount, popularNextCursor != nil {
            guard !isLoadingMoreDiscovery else { return }
            await loadMoreDiscoveryPage(section: .popular)
        }
    }

    func loadMoreDiscoveryIfNeeded(currentRoomID: RoomID) async {
        guard !isLoadingMoreDiscovery else { return }

        if activeDiscoveryScope == .all {
            return
        }

        guard activeDiscoveryScope.showsUnifiedDiscoveryList else { return }
        guard let last = unifiedDiscoverableRooms.last?.id,
              last == currentRoomID,
              popularNextCursor != nil
        else { return }
        await loadMoreDiscoveryPage(section: .popular)
    }

    private func loadMoreDiscoveryPage(section: TradeRoomDiscoveryMode) async {
        guard section == .suggested || section == .popular else { return }
        guard let viewerID else { return }
        isLoadingMoreDiscovery = true
        defer { isLoadingMoreDiscovery = false }
        do {
            let bootstrap = try await explore.tradeRoomsHomeBootstrap(
                scope: discoveryScope.bootstrapCacheScope,
                limit: discoveryPageFetchLimit,
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
        TradeRoomDiscoveryMemberCountCache.record(room)
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
                await self?.domain.refreshRooms()
            }
        )

        if result == .joined {
            patchDiscoveryRoomJoined(room.id)
            insertJoinedYourRoomIfNeeded(room)
            Task { await domain.refreshRooms() }
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
        let isJoined = joinedRoomIDs.contains(roomID)
        if isJoined { return .joined }
        let pool = yourRoomsItems + suggestedItems + popularItems + searchDiscoveryRooms
        guard let room = pool.first(where: { $0.id == roomID }) else {
            return joinCoordinator.mutationStates[roomID] ?? .idle
        }
        return joinCoordinator.effectiveState(
            for: room,
            isJoined: isJoined
        )
    }

    func searchChanged() {
        searchTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchDiscoveryRooms = []
            searchDiscoveryPhase = .idle
            return
        }

        searchDiscoveryRooms = localDiscoveryMatches(for: query)
        searchDiscoveryPhase = searchDiscoveryRooms.isEmpty ? .loading : .loaded

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.searchDebounceNanoseconds)
            guard !Task.isCancelled, let self else { return }
            await self.performSearchDiscovery(query: query, generation: generation)
        }
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
            return TradeRoomMembershipSync.patchExploreRoomSuggestion(updated)
        }
    }

    private func patchDiscoveryRoomLeft(_ roomID: RoomID) {
        patchDiscoverableCollections(roomID: roomID) { room in
            var updated = room
            updated.isJoined = false
            updated.isMember = false
            return updated
        }
        yourRoomsItems.removeAll { $0.id == roomID }
    }

    private func ownedRoomSuggestion(from room: TradeRoom) -> ExploreRoomSuggestion {
        let ownerItem = items.first(where: { $0.id == room.id })
        return ExploreRoomSuggestion.fromMembership(
            room: room,
            ownerName: ownerItem?.ownerName,
            ownerUsername: nil,
            viewerID: viewerID,
            isOwner: true,
            isMember: true
        )
    }

    private func upsertOwnedRoomInYourRooms(_ room: TradeRoom) {
        let row = ownedRoomSuggestion(from: room)
        var copy = row
        copy.isOwner = true
        copy.isMember = true
        copy.isJoined = true
        if let index = yourRoomsItems.firstIndex(where: { $0.id == room.id }) {
            yourRoomsItems[index] = copy
        } else {
            yourRoomsItems.insert(copy, at: 0)
        }
    }

    /// Keeps All/Popular payloads aligned after create — filtering also hides owned rows client-side.
    private func stripViewerOwnedRoomFromDiscoverablePayloads(roomID: RoomID) {
        suggestedItems.removeAll { $0.id == roomID }
        popularItems.removeAll { $0.id == roomID }
        searchDiscoveryRooms.removeAll { $0.id == roomID }
    }

    private func insertJoinedYourRoomIfNeeded(_ room: ExploreRoomSuggestion) {
        var row = TradeRoomMembershipSync.patchExploreRoomSuggestion(room)
        row.isMember = true
        row.isJoined = true
        guard !yourRoomsItems.contains(where: { $0.id == row.id }) else {
            if let index = yourRoomsItems.firstIndex(where: { $0.id == row.id }) {
                yourRoomsItems[index] = row
            }
            return
        }
        yourRoomsItems.append(row)
        yourRoomsItems.sort { lhs, rhs in
            if lhs.viewerIsOwner != rhs.viewerIsOwner { return lhs.viewerIsOwner }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func syncMembershipPresentationFromStore() {
        suggestedItems = TradeRoomMembershipSync.applyMembershipFlags(to: suggestedItems)
        popularItems = TradeRoomMembershipSync.applyMembershipFlags(to: popularItems)
        searchDiscoveryRooms = TradeRoomMembershipSync.applyMembershipFlags(to: searchDiscoveryRooms)
        yourRoomsItems = TradeRoomMembershipSync.applyMembershipFlags(to: yourRoomsItems)
        for id in TradeRoomMembershipStore.shared.allJoinedRoomIDs {
            if let room = (suggestedItems + popularItems + searchDiscoveryRooms).first(where: { $0.id == id }) {
                insertJoinedYourRoomIfNeeded(room)
            }
        }
        _ = reconcileYourRoomsWithMembership()
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
        if let index = searchDiscoveryRooms.firstIndex(where: { $0.id == roomID }) {
            searchDiscoveryRooms[index] = transform(searchDiscoveryRooms[index])
        }
    }

    private func localDiscoveryMatches(for query: String) -> [ExploreRoomSuggestion] {
        func matches(_ room: ExploreRoomSuggestion) -> Bool {
            room.name.localizedCaseInsensitiveContains(query)
                || room.slug.localizedCaseInsensitiveContains(query)
                || (room.description?.localizedCaseInsensitiveContains(query) ?? false)
                || room.discoveryTags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        var seen = Set<RoomID>()
        var merged: [ExploreRoomSuggestion] = []
        for room in yourRoomsItems + suggestedItems + popularItems {
            guard matches(room), !seen.contains(room.id) else { continue }
            seen.insert(room.id)
            merged.append(room)
        }
        return merged
    }

    private func mergeSearchDiscoveryRows(
        local: [ExploreRoomSuggestion],
        remote: [ExploreRoomSuggestion]
    ) -> [ExploreRoomSuggestion] {
        var seen = Set(local.map(\.id))
        var merged = local
        for row in remote where !seen.contains(row.id) {
            merged.append(row)
            seen.insert(row.id)
        }
        for row in remote {
            if let index = merged.firstIndex(where: { $0.id == row.id }) {
                merged[index] = row
            }
        }
        return merged
    }

    private func performSearchDiscovery(query: String, generation: UInt64) async {
        searchDiscoveryPhase = .loading
        let local = localDiscoveryMatches(for: query)
        do {
            let remote = try await explore.searchRooms(
                query: query,
                limit: Self.searchDiscoveryLimit
            )
            guard !Task.isCancelled, generation == searchGeneration else { return }
            searchDiscoveryRooms = mergeSearchDiscoveryRows(local: local, remote: remote)
            searchDiscoveryPhase = .loaded
        } catch {
            guard !Task.isCancelled, generation == searchGeneration else { return }
            searchDiscoveryRooms = local
            searchDiscoveryPhase = .loaded
            if searchDiscoveryRooms.isEmpty {
                discoveryErrorMessage = ProfileSectionSupport.message(for: error)
            }
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
        if let viewerID {
            detailCache.seedOwnedTradeRoom(room, for: viewerID)
            TradeRoomCreationIntent.shared.noteCreatedRoom(room)
            upsertOwnedRoomInYourRooms(room)
            syncOwnedTradeRoomPresentationFromLocalStores()
            stripViewerOwnedRoomFromDiscoverablePayloads(roomID: room.id)
        }
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

    func isRoomFavorited(_ roomID: RoomID) -> Bool {
        TradeRoomFavoritesStore.shared.isFavorited(roomID)
    }

    func toggleFavorite(roomID: RoomID) async {
        guard let viewerID else { return }
        _ = await TradeRoomFavoriteAction.toggle(
            roomID: roomID,
            viewerID: viewerID,
            rooms: rooms
        )
        syncFavoritePresentation()
    }

    func syncFavoritePresentation() {
        yourRoomsItems = TradeRoomFavoriteSync.applyFavoritedFlag(to: yourRoomsItems)
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
            TradeRoomMembershipSync.applyLeft(
                roomID: id,
                viewerID: viewerID,
                inboxStore: inboxStore
            )
            SessionTradeRoomsDiscoveryStore.shared.invalidate(viewerID: viewerID)
            yourRoomsItems.removeAll { $0.id == id }
            patchDiscoveryRoomLeft(id)
            TradeRoomFavoritesStore.shared.setFavorited(id, favorited: false)
            Task { await domain.refreshRooms() }
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
        TradeRoomMembershipStore.shared.mergeServerMembership(Set(inboxStore.rooms.map(\.id)))
        _ = reconcileYourRoomsWithMembership()
        syncMembershipPresentationFromStore()
        syncOwnedTradeRoomPresentationFromLocalStores()
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

    private func bootstrapFetchLimit(for scope: TradeRoomDiscoveryScope) -> Int {
        _ = scope
        return Self.discoveryInitialLimit
    }

    private var discoveryPageFetchLimit: Int {
        activeDiscoveryScope == .all
            ? Self.allScopeDiscoveryPageSize
            : Self.discoveryInitialLimit
    }

    private func filteredDiscoverable(
        from source: [ExploreRoomSuggestion],
        section: String,
        excludeViewerOwnedRoom: Bool = false
    ) -> [ExploreRoomSuggestion] {
        let filtered = source.filter { room in
            guard !joinedRoomIDs.contains(room.id) else { return false }
            if excludeViewerOwnedRoom, isViewerOwnedDiscoveryRoom(room) { return false }
            return true
        }
        #if DEBUG
        RoomDiscoveryProbe.logClientFilter(
            section: section,
            before: source.count,
            after: filtered.count,
            reason: excludeViewerOwnedRoom
                ? "alreadyJoinedOrViewerOwned"
                : "alreadyJoinedInInbox"
        )
        #endif
        return filtered
    }

    /// Joined list presentation — owned room always first (member-count order from RPC ignored).
    private func joinedDiscoveryRoomsOrdered() -> [ExploreRoomSuggestion] {
        let pinnedOwned = viewerOwnedRoom
            ?? yourRoomsItems.first(where: isViewerOwnedDiscoveryRoom)
        guard let pinnedOwned else { return yourRoomsItems }
        var remainder = yourRoomsItems.filter { $0.id != pinnedOwned.id }
        remainder.sort { lhs, rhs in
            if lhs.viewerIsOwner != rhs.viewerIsOwner { return lhs.viewerIsOwner }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return [pinnedOwned] + remainder
    }

    private func isViewerOwnedDiscoveryRoom(_ room: ExploreRoomSuggestion) -> Bool {
        if room.viewerIsOwner { return true }
        if let viewerID, room.ownerProfileID == viewerID { return true }
        if let ownedID = viewerOwnedRoom?.id, room.id == ownedID { return true }
        return false
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
            await TradeRoomFavoriteAction.hydrateIfNeeded(viewerID: sessionViewer, rooms: rooms)
            syncFavoritePresentation()
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
            yourRoomsItems = TradeRoomFavoriteSync.applyFavoritedFlag(to: bootstrap.yourRooms)
            suggestedItems = bootstrap.suggested
            popularItems = bootstrap.popular
            let serverJoined = Set(
                bootstrap.yourRooms
                    .filter { $0.viewerIsMember || $0.viewerIsOwner }
                    .map(\.id)
            )
            TradeRoomMembershipStore.shared.mergeServerMembership(serverJoined)
            suggestedItems = TradeRoomMembershipSync.applyMembershipFlags(to: suggestedItems)
            popularItems = TradeRoomMembershipSync.applyMembershipFlags(to: popularItems)
            yourRoomsItems = TradeRoomMembershipSync.applyMembershipFlags(to: yourRoomsItems)
            applyDiscoveryPagination(from: bootstrap)
            if discoveryScope == .all {
                allScopeVisibleCount = Self.allScopeDiscoveryPageSize
            }
        }

        _ = reconcileYourRoomsWithMembership()
        syncFavoritePresentation()
        syncOwnedTradeRoomPresentationFromLocalStores()
        if bootstrapChanged {
            logDisplayedIfChanged(source: source)
        }
    }

    /// Keeps ``DetailPresentationCache`` aligned with inbox / bootstrap — no network.
    func syncOwnedTradeRoomPresentationFromLocalStores() {
        guard let viewerID else { return }
        if let item = items.first(where: { $0.room.ownerProfileID == viewerID }) {
            if detailCache.ownedTradeRoom(for: viewerID)?.id != item.room.id {
                detailCache.seedOwnedTradeRoom(item.room, for: viewerID)
            }
            return
        }
        if let owned = yourRoomsItems.first(where: \.viewerIsOwner),
           let inboxRoom = inboxStore.rooms.first(where: { $0.id == owned.id })
        {
            detailCache.seedOwnedTradeRoom(inboxRoom, for: viewerID)
        }
    }

    /// One authoritative owner lookup when local stores miss (e.g. stale profile `nil` cache).
    func refreshOwnedTradeRoomHeaderIfNeeded() async {
        guard let viewerID else { return }
        if viewerOwnedRoom != nil { return }

        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) {
            let room = TradeRoomsFixtures.rooms(ownerID: viewerID).first
            detailCache.seedOwnedTradeRoom(room, for: viewerID)
            if let room { upsertOwnedRoomInYourRooms(room) }
            return
        }

        if let room = try? await rooms.ownedRoom(for: viewerID) {
            detailCache.seedOwnedTradeRoom(room, for: viewerID)
            upsertOwnedRoomInYourRooms(room)
            return
        }

        if !detailCache.hasResolvedOwnedTradeRoom(for: viewerID), inboxStore.hasLoadedRooms {
            detailCache.seedOwnedTradeRoom(nil, for: viewerID)
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
