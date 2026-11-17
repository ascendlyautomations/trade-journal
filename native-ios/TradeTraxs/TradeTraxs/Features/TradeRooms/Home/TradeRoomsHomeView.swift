import SwiftUI

/// Dedicated Trade Rooms home — member rooms with search, refresh, and empty/error states.
struct TradeRoomsHomeView: View {
    @State private var viewModel: TradeRoomsHomeViewModel
    private let data: DataEnvironment?
    private let imagePipeline: any ImagePipeline
    private let armPresentCreateOnAppear: Bool
    private let navigationHost: TradeRoomNavigationHost

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tabIsActive) private var tabIsActive
    @Bindable private var favoritesStore = TradeRoomFavoritesStore.shared
    @Bindable private var membershipStore = TradeRoomMembershipStore.shared
    @Bindable private var inboxStore = MessagesInboxStore.shared

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        navigationHost: TradeRoomNavigationHost = .messages,
        presentCreateOnAppear: Bool = false
    ) {
        self.armPresentCreateOnAppear = presentCreateOnAppear
        self.navigationHost = navigationHost
        _viewModel = State(
            initialValue: TradeRoomsHomeScreenStore.viewModel(host: navigationHost) {
                TradeRoomsHomeViewModel(
                    messages: data.messages,
                    rooms: data.rooms,
                    explore: data.explore,
                    profiles: data.profiles,
                    session: data.session,
                    detailCache: data.detailCache,
                    navigationCoordinator: navigationCoordinator,
                    navigationHost: navigationHost,
                    realtimeHub: data.realtimeHub,
                    presentCreateOnAppear: false
                )
            }
        )
        self.data = data
        self.imagePipeline = data.imagePipeline
    }

    /// Tests / previews.
    init(viewModel: TradeRoomsHomeViewModel, imagePipeline: any ImagePipeline) {
        _viewModel = State(initialValue: viewModel)
        self.data = nil
        self.imagePipeline = imagePipeline
        self.armPresentCreateOnAppear = false
        self.navigationHost = .messages
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                if !viewModel.items.isEmpty {
                    roomList
                } else {
                    TradeRoomsSkeleton()
                }
            case .failed(let message):
                if !viewModel.items.isEmpty {
                    roomList
                } else {
                    ExperienceErrorState(
                        title: "Couldn't load Trade Rooms",
                        message: message,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                }
            case .loaded where viewModel.showsEmpty && !viewModel.hasDiscoverableRooms && viewModel.discoveryPhase != .loading:
                ExperienceEmptyState(
                    icon: .rooms,
                    title: "No Trade Rooms yet",
                    message: "Create your own Trade Room or join a community room to trade ideas with other traders.",
                    actionTitle: viewModel.viewerOwnedRoom == nil ? "Create Trade Room" : nil,
                    action: viewModel.viewerOwnedRoom == nil ? { viewModel.presentCreateRoom() } : nil
                )
            case .loaded:
                roomList
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Trade Rooms")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let _ = inboxStore.rooms
                headerOwnershipAction
            }
        }
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search rooms"
        )
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.searchChanged()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onAppear {
            ActiveScreenBootstrapPriorityGate.tradeRooms.setScreenActive(true)
            viewModel.setHostingTabActive(tabIsActive)
            viewModel.noteViewAppeared()
            if let scope = TradeRoomsHomeScreenStore.consumePendingDiscoveryScope(for: navigationHost) {
                viewModel.selectDiscoveryScope(TradeRoomDiscoveryScope.normalizedHomeScope(scope))
            }
            if armPresentCreateOnAppear || TradeRoomCreationIntent.shared.consumePresentCreate() {
                viewModel.armPresentCreateOnAppear()
            }
            viewModel.consumePresentCreateIfNeeded()
        }
        .onDisappear {
            ActiveScreenBootstrapPriorityGate.tradeRooms.setScreenActive(false)
            viewModel.setHostingTabActive(false)
            viewModel.noteViewDisappeared()
            viewModel.releaseRealtime()
        }
        .onChange(of: tabIsActive) { _, isActive in
            viewModel.setHostingTabActive(isActive)
            ActiveScreenBootstrapPriorityGate.tradeRooms.setScreenActive(isActive)
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .onChange(of: viewModel.phase) { _, _ in
            viewModel.consumePresentCreateIfNeeded()
        }
        .onChange(of: viewModel.discoveryPhase) { _, _ in
            viewModel.consumePresentCreateIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradeRoomMetadataDidChange)) { notification in
            guard let room = notification.tradeRoomMetadataPayload else { return }
            viewModel.applyRoomMetadata(room)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradeRoomFavoriteDidChange)) { _ in
            viewModel.syncFavoritePresentation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradeRoomMembershipDidChange)) { _ in
            viewModel.syncMembershipPresentationFromStore()
        }
        .confirmationDialog(
            "Leave this Trade Room?",
            isPresented: Binding(
                get: { viewModel.showsLeaveRoomConfirmation },
                set: { presented in
                    if !presented { viewModel.cancelLeaveRoom() }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Leave Room", role: .destructive) {
                Task { await viewModel.confirmLeaveRoom() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelLeaveRoom()
            }
        } message: {
            Text("You can rejoin later if the room is still available.")
        }
        .sheet(isPresented: $viewModel.showsCreateRoom) {
            if let data {
                CreateRoomView(
                    data: data,
                    onDismiss: { viewModel.showsCreateRoom = false },
                    onCreated: { room in viewModel.handleRoomCreated(room) }
                )
            }
        }
    }

    @ViewBuilder
    private var headerOwnershipAction: some View {
        if viewModel.isHeaderOwnershipResolved {
            if let ownedRoom = viewModel.viewerOwnedRoom {
                Button(action: { viewModel.openOwnedRoom() }) {
                    TradeRoomCircularAvatar(
                        imageReference: ownedRoom.imageReference,
                        imagePipeline: imagePipeline,
                        diameter: 32
                    )
                    .frame(
                        width: ExperienceAccessibility.minTouchTarget,
                        height: ExperienceAccessibility.minTouchTarget
                    )
                    .contentShape(Circle())
                }
                .buttonStyle(.experiencePlain)
                .accessibilityLabel("Your Room")
                .accessibilityIdentifier("tradeRooms.yourRoom")
            } else {
                Button(action: { viewModel.presentCreateRoom() }) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(
                            width: ExperienceAccessibility.minTouchTarget,
                            height: ExperienceAccessibility.minTouchTarget
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Create Trade Room")
                .accessibilityIdentifier("tradeRooms.create")
            }
        }
    }

    /// Force Observation of shared room unread so badges clear without leave/refresh.
    private var roomUnreadObservation: [RoomID: Int] {
        MessagesInboxStore.shared.roomUnread
    }

    @ViewBuilder
    private var roomList: some View {
        let _ = roomUnreadObservation
        let _ = favoritesStore.revision
        if viewModel.showsDiscoverySection {
            discoveryRoomScrollList
        } else {
            tradeRoomsSearchResultsContent
        }
    }

    private var discoveryRoomScrollList: some View {
        ScrollView {
            LazyVStack(spacing: ExperienceSpacing.sm) {
                discoverySection
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.bottom, ExperienceSpacing.sm)
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("tradeRooms.list")
    }

    @ViewBuilder
    private var tradeRoomsSearchResultsContent: some View {
        if viewModel.searchDiscoveryPhase == .loading,
           viewModel.searchDiscoveryDisplayRooms.isEmpty,
           viewModel.filteredItems.isEmpty
        {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("tradeRooms.search.loading")
        } else if viewModel.showsFilteredEmpty {
            ExperienceEmptyState(
                icon: .search,
                title: "No matches",
                message: "Try a different room name or keyword."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("tradeRooms.search.empty")
        } else {
            tradeRoomsSearchResultsList
        }
    }

    private var tradeRoomsSearchResultsList: some View {
        List {
            ForEach(viewModel.searchDiscoveryDisplayRooms) { room in
                discoveryRow(for: room, isYourRoomsContext: false, presentation: .plainList)
                    .listRowBackground(colors.backgroundPrimary)
                    .accessibilityIdentifier("tradeRooms.search.discovery.\(room.id.rawValue)")
            }

            ForEach(viewModel.filteredItems) { item in
                TradeRoomInboxSearchListRow(
                    item: item,
                    imagePipeline: imagePipeline,
                    onOpen: { viewModel.openRoom(item) }
                )
                .listRowBackground(colors.backgroundPrimary)
                .contextMenu {
                    Button {
                        Task { await viewModel.toggleFavorite(roomID: item.id) }
                    } label: {
                        Label(
                            viewModel.isRoomFavorited(item.id) ? "Unfavorite Room" : "Favorite Room",
                            systemImage: viewModel.isRoomFavorited(item.id) ? "star.fill" : "star"
                        )
                    }
                }
            }

            if viewModel.searchDiscoveryPhase == .loading,
               viewModel.searchDiscoveryDisplayRooms.isEmpty,
               !viewModel.filteredItems.isEmpty
            {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("tradeRooms.search.loadingMore")
            }
        }
        .experiencePlainListStyle()
        .accessibilityIdentifier("tradeRooms.search.results")
    }

    @ViewBuilder
    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            let _ = membershipStore.revision
            TradeRoomDiscoveryScopeToggle(
                scope: viewModel.activeDiscoveryScope,
                onSelect: { viewModel.selectDiscoveryScope($0) }
            )
            .padding(.top, ExperienceSpacing.sm)
            .padding(.bottom, ExperienceSpacing.xxs)

            if viewModel.discoveryPhase == .loading,
               viewModel.activeDiscoveryScope.showsDiscoverableLists,
               discoveryListsAreEmpty
            {
                discoverySkeleton
            } else if viewModel.discoveryPhase == .loading,
                      viewModel.activeDiscoveryScope.showsYourRoomsDiscovery,
                      viewModel.yourRooms.isEmpty
            {
                discoverySkeleton
            } else if let message = viewModel.discoveryErrorMessage,
                      viewModel.activeDiscoveryScope.showsDiscoverableLists,
                      discoveryListsAreEmpty
            {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    Text(message)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                    Button("Retry") {
                        viewModel.retryDiscovery()
                    }
                    .font(.footnote.weight(.semibold))
                }
                .padding(.vertical, ExperienceSpacing.xs)
            } else {
                if viewModel.activeDiscoveryScope.showsAllScopeUnifiedDiscoveryList {
                    allScopeDiscoverySection
                }

                if viewModel.activeDiscoveryScope.showsUnifiedDiscoveryList {
                    unifiedDiscoverySection
                }

                if viewModel.activeDiscoveryScope.showsFavoritesDiscovery {
                    favoritesDiscoverySection
                }

                if viewModel.activeDiscoveryScope.showsYourRoomsDiscovery {
                    yourRoomsDiscoverySection(showsSectionHeader: false)
                }
            }
        }
        .padding(.bottom, ExperienceSpacing.sm)
        .accessibilityIdentifier("tradeRooms.discovery.section")
    }

    private var discoveryListsAreEmpty: Bool {
        if viewModel.activeDiscoveryScope.showsAllScopeUnifiedDiscoveryList {
            return viewModel.allScopeDiscoverableRooms.isEmpty
        }
        if viewModel.activeDiscoveryScope.showsUnifiedDiscoveryList {
            return viewModel.unifiedDiscoverableRooms.isEmpty
        }
        return viewModel.suggestedDiscoverableRooms.isEmpty
            && viewModel.popularDiscoverableRooms.isEmpty
    }

    private var allScopeDiscoverySection: some View {
        let rooms = viewModel.allScopeDisplayedDiscoverableRooms
        let emptyMessage = viewModel.activeDiscoveryScope.allScopeDiscoveryEmptyMessage
        return VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if rooms.isEmpty, viewModel.discoveryPhase == .loaded {
                Text(emptyMessage)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else {
                ForEach(rooms) { room in
                    discoveryRow(for: room, isYourRoomsContext: false)
                }

                if viewModel.showsAllScopeShowMore {
                    Button {
                        viewModel.showMoreAllScopeDiscovery()
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isLoadingMoreDiscovery {
                                ProgressView()
                            } else {
                                Text("Show More")
                                    .font(.subheadline.weight(.semibold))
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.experiencePlain)
                    .disabled(viewModel.isLoadingMoreDiscovery)
                    .accessibilityIdentifier("tradeRooms.all.showMore")
                }
            }
        }
    }

    private var unifiedDiscoverySection: some View {
        let rooms = viewModel.unifiedDiscoverableRooms
        let emptyMessage = viewModel.activeDiscoveryScope.unifiedDiscoveryEmptyMessage
        return VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if rooms.isEmpty, viewModel.discoveryPhase == .loaded {
                Text(emptyMessage)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else {
                ForEach(rooms) { room in
                    discoveryRow(for: room, isYourRoomsContext: false)
                        .onAppear {
                            Task {
                                await viewModel.loadMoreDiscoveryIfNeeded(currentRoomID: room.id)
                            }
                        }
                }
            }
        }
    }

    private var favoritesDiscoverySection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if viewModel.favoriteRooms.isEmpty, viewModel.discoveryPhase == .loaded {
                ExperienceEmptyState(
                    icon: .rooms,
                    title: "No favorites yet",
                    message: "Press and hold a joined room to favorite it and pin it here."
                )
                .padding(.vertical, ExperienceSpacing.xs)
            } else {
                ForEach(viewModel.favoriteRooms) { room in
                    discoveryRow(for: room, isYourRoomsContext: true)
                }
            }
        }
    }

    @ViewBuilder
    private func yourRoomsDiscoverySection(showsSectionHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if showsSectionHeader {
                discoverySectionHeader(TradeRoomDiscoveryMode.yourRooms.title)
            }

            if viewModel.yourRooms.isEmpty, viewModel.discoveryPhase == .loaded {
                ExperienceEmptyState(
                    icon: .rooms,
                    title: "No rooms yet",
                    message: TradeRoomDiscoveryMode.yourRooms.emptyMessage,
                    actionTitle: viewModel.viewerOwnedRoom == nil ? "Create Trade Room" : nil,
                    action: viewModel.viewerOwnedRoom == nil ? { viewModel.presentCreateRoom() } : nil
                )
                .padding(.vertical, ExperienceSpacing.xs)
            } else if viewModel.yourRooms.isEmpty {
                Text(TradeRoomDiscoveryMode.yourRooms.emptyMessage)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else {
                ForEach(viewModel.yourRooms) { room in
                    discoveryRow(for: room, isYourRoomsContext: true)
                }
            }
        }
    }

    private func discoverySectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.caption2, design: .default).weight(.semibold))
            .foregroundStyle(colors.secondaryText)
            .textCase(.uppercase)
            .tracking(0.35)
            .padding(.bottom, ExperienceSpacing.xxs)
    }

    @ViewBuilder
    private func discoveryRoomSection(
        title: String,
        rooms: [ExploreRoomSuggestion],
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            discoverySectionHeader(title)
            if rooms.isEmpty, viewModel.discoveryPhase == .loaded {
                Text(emptyMessage)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else {
                ForEach(rooms) { room in
                    discoveryRow(for: room, isYourRoomsContext: false)
                        .onAppear {
                            Task {
                                await viewModel.loadMoreDiscoveryIfNeeded(currentRoomID: room.id)
                            }
                        }
                }
            }
        }
    }

    private func discoveryRow(
        for room: ExploreRoomSuggestion,
        isYourRoomsContext: Bool,
        presentation: TradeRoomDiscoveryRow.Presentation = .elevatedCard
    ) -> some View {
        let showsMembershipActions = isYourRoomsContext
            && (room.viewerIsMember || room.viewerIsOwner)
        return TradeRoomDiscoveryRow(
            room: room,
            joinState: viewModel.joinState(for: room.id),
            isYourRoomsContext: isYourRoomsContext,
            isOwner: viewModel.isViewerOwner(of: room),
            presentation: presentation,
            imagePipeline: imagePipeline,
            onOpen: { viewModel.openDiscoveryRoom(room) },
            onJoin: { Task { await viewModel.joinDiscoveryRoom(room) } },
            isFavorited: viewModel.isRoomFavorited(room.id),
            onToggleFavorite: showsMembershipActions
                ? { Task { await viewModel.toggleFavorite(roomID: room.id) } }
                : nil
        )
    }

    private var discoverySkeleton: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: ExperienceSpacing.sm) {
                    Circle()
                        .fill(colors.fillSecondary)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colors.fillSecondary)
                            .frame(width: 160, height: 14)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colors.fillSecondary)
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colors.fillSecondary)
                            .frame(width: 100, height: 10)
                    }
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(colors.fillSecondary)
                        .frame(width: 64, height: 32)
                }
                .padding(ExperienceSpacing.sm)
                .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.lg))
                .redacted(reason: .placeholder)
            }
        }
    }

}
