import SwiftUI

/// Dedicated Trade Rooms home — member rooms with search, refresh, and empty/error states.
struct TradeRoomsHomeView: View {
    @State private var viewModel: TradeRoomsHomeViewModel
    private let data: DataEnvironment?
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        navigationHost: TradeRoomNavigationHost = .messages,
        presentCreateOnAppear: Bool = false
    ) {
        _viewModel = State(
            initialValue: TradeRoomsHomeViewModel(
                messages: data.messages,
                rooms: data.rooms,
                explore: data.explore,
                profiles: data.profiles,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                navigationHost: navigationHost,
                realtimeHub: data.realtimeHub,
                presentCreateOnAppear: presentCreateOnAppear
                    || TradeRoomCreationIntent.shared.consumePresentCreate()
            )
        )
        self.data = data
        self.imagePipeline = data.imagePipeline
    }

    /// Tests / previews.
    init(viewModel: TradeRoomsHomeViewModel, imagePipeline: any ImagePipeline) {
        _viewModel = State(initialValue: viewModel)
        self.data = nil
        self.imagePipeline = imagePipeline
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
                headerOwnershipAction
            }
        }
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search rooms"
        )
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .onDisappear {
            viewModel.releaseRealtime()
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
            if viewModel.viewerOwnedRoom != nil {
                Button(action: { viewModel.openOwnedRoom() }) {
                    Text("Your Room")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.onAccent)
                        .padding(.horizontal, ExperienceSpacing.sm)
                        .padding(.vertical, 6)
                        .background(colors.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tradeRooms.yourRoom")
            } else {
                Button(action: { viewModel.presentCreateRoom() }) {
                    Label("Create Trade Room", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("tradeRooms.create")
            }
        }
    }

    /// Force Observation of shared room unread so badges clear without leave/refresh.
    private var roomUnreadObservation: [RoomID: Int] {
        MessagesInboxStore.shared.roomUnread
    }

    private var roomList: some View {
        let _ = roomUnreadObservation
        return ScrollView {
            LazyVStack(spacing: ExperienceSpacing.sm) {
                if viewModel.showsDiscoverySection {
                    discoverySection
                }

                if viewModel.showsFilteredEmpty {
                    ExperienceEmptyState(
                        icon: .search,
                        title: "No matches",
                        message: "Try a different room name or owner."
                    )
                    .padding(.top, ExperienceSpacing.xl)
                }

                if !viewModel.filteredItems.isEmpty, !viewModel.showsDiscoverySection {
                    ForEach(viewModel.filteredItems) { item in
                    Button {
                        viewModel.openRoom(item)
                    } label: {
                        TradeRoomCardView(item: item, imagePipeline: imagePipeline)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            viewModel.openRoom(item)
                        } label: {
                            Label("Open", systemImage: "person.3")
                        }
                        Button {
                            viewModel.toggleMute(roomID: item.id)
                        } label: {
                            Label(
                                item.isMuted ? "Unmute" : "Mute",
                                systemImage: item.isMuted ? "bell.fill" : "bell.slash.fill"
                            )
                        }
                        Divider()
                        Button(role: .destructive) {
                            viewModel.requestLeaveRoom(id: item.id)
                        } label: {
                            Label("Leave Room", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } preview: {
                        TradeRoomCardView(item: item, imagePipeline: imagePipeline)
                            .frame(width: 320)
                            .padding()
                    }
                    }
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: viewModel.searchText)
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("tradeRooms.list")
    }

    @ViewBuilder
    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            TradeRoomDiscoveryModeToggle(
                mode: viewModel.discoveryMode,
                onSelect: { viewModel.selectDiscoveryMode($0) }
            )

            TradeRoomDiscoveryScopeToggle(
                scope: viewModel.discoveryScope,
                onSelect: { viewModel.selectDiscoveryScope($0) }
            )

            if viewModel.discoveryMode != .yourRooms {
                Text("Discover rooms")
                    .experienceStyle(.subheadline, color: colors.secondaryText)
            }

            if viewModel.discoveryPhase == .loading, viewModel.displayedDiscoveryRooms.isEmpty {
                discoverySkeleton
            } else if let message = viewModel.discoveryErrorMessage,
                      viewModel.displayedDiscoveryRooms.isEmpty,
                      viewModel.discoveryMode != .yourRooms
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
            } else if viewModel.showsYourRoomsEmptyState {
                ExperienceEmptyState(
                    icon: .rooms,
                    title: "No rooms yet",
                    message: viewModel.discoveryMode.emptyMessage
                )
                .padding(.vertical, ExperienceSpacing.sm)
            } else if viewModel.displayedDiscoveryRooms.isEmpty {
                Text(viewModel.discoveryMode.emptyMessage)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .padding(.vertical, ExperienceSpacing.xs)
            } else {
                ForEach(viewModel.displayedDiscoveryRooms) { room in
                    TradeRoomDiscoveryRow(
                        room: room,
                        joinState: viewModel.joinState(for: room.id),
                        isYourRoomsContext: viewModel.discoveryMode == .yourRooms,
                        isOwner: viewModel.isViewerOwner(of: room),
                        imagePipeline: imagePipeline,
                        onOpen: { viewModel.openDiscoveryRoom(room) },
                        onJoin: { Task { await viewModel.joinDiscoveryRoom(room) } }
                    )
                }
            }
        }
        .padding(.bottom, ExperienceSpacing.sm)
        .accessibilityIdentifier("tradeRooms.discovery.section")
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
