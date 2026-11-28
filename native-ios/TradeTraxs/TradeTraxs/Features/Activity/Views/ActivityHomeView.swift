import SwiftUI

struct ActivityHomeView: View {
    @State private var viewModel: ActivityHomeViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        navigationHost: ActivityNavigationHost = .home
    ) {
        _viewModel = State(
            initialValue: ActivityHomeViewModel(
                notifications: data.notifications,
                followRequests: data.followRequests,
                profiles: data.profiles,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                navigationHost: navigationHost,
                realtimeHub: data.realtimeHub,
                inboxStore: .shared,
                router: NotificationRouter(),
                rpc: data.rpc
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    init(
        viewModel: ActivityHomeViewModel,
        imagePipeline: any ImagePipeline,
        navigationHost: ActivityNavigationHost = .home
    ) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
    }

    var body: some View {
        VStack(spacing: 0) {
            ActivityNotificationFilterBar(viewModel: viewModel)
            Group {
                switch viewModel.phase {
                case .idle, .loading:
                    if viewModel.sections.isEmpty && (viewModel.phase == .loading || viewModel.isReloadingFiltered) {
                        ExperienceListSkeleton(style: .inboxRow, rowCount: 8)
                    } else {
                        listContent
                    }
                case .failed(let message):
                    if viewModel.sections.isEmpty {
                        ExperienceErrorState(
                            title: "Couldn't load Activity",
                            message: message,
                            onRetry: { Task { await viewModel.refresh() } }
                        )
                    } else {
                        listContent
                    }
                case .loaded:
                    if viewModel.isReloadingFiltered && viewModel.sections.isEmpty {
                        ExperienceListSkeleton(style: .inboxRow, rowCount: 8)
                    } else if viewModel.showsEmpty {
                        ExperienceEmptyState(
                            icon: .activity,
                            title: viewModel.emptyStateTitle,
                            message: viewModel.emptyStateMessage
                        )
                    } else {
                        listContent
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showsCustomDateSheet) {
            ActivityCustomDateRangeSheet(viewModel: viewModel)
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Activity")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if viewModel.unreadCount > 0 {
                        Button("Mark All as Read") {
                            viewModel.markAllRead()
                        }
                    }
                    Button("Notification Settings") {
                        viewModel.openNotificationSettings()
                    }
                } label: {
                    ExperienceIcon(icon: .more, size: .md, color: colors.primaryText)
                    .experienceControlHitTarget()
                }
                .accessibilityLabel("Activity options")
                .accessibilityIdentifier("activity.menu")
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            ActivityFeedBootstrapPriorityGate.setScreenActive(true)
            viewModel.loadIfNeeded()
        }
        .onDisappear {
            ActivityFeedBootstrapPriorityGate.setScreenActive(false)
        }
        .accessibilityIdentifier("activity.home")
    }

    private var listContent: some View {
        activityList
            .listSectionSpacing(ActivityInboxLayout.sectionSpacing)
            .contentMargins(.top, ActivityInboxLayout.listTopContentMargin, for: .scrollContent)
            .experiencePlainListStyle()
    }

    private var activityList: some View {
        List {
            activityFollowRequestsSection
            activityNotificationSections
            activityLoadingMoreSection
        }
    }

    @ViewBuilder
    private var activityFollowRequestsSection: some View {
        if viewModel.pendingFollowRequestCount > 0 {
            Section {
                ActivityFollowRequestsBanner(
                    count: viewModel.pendingFollowRequestCount,
                    action: { viewModel.openFollowRequests() }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var activityNotificationSections: some View {
        ForEach(viewModel.sections) { section in
            Section {
                ForEach(section.rows) { row in
                    ActivityInboxRowListItem(
                        row: row,
                        colors: colors,
                        imagePipeline: imagePipeline,
                        onOpen: { viewModel.open(row) },
                        onOpenActor: { viewModel.openActor($0) },
                        onDelete: { viewModel.delete(row: row) },
                        onMarkRead: { viewModel.markRead(row: row) },
                        onMarkUnread: { viewModel.markUnread(row: row) },
                        onAppear: { viewModel.loadMoreIfNeeded(currentID: row.id) }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(colors.backgroundPrimary)
                    .listRowSeparator(.hidden)
                }
            } header: {
                Text(section.section.rawValue)
            }
        }
    }

    @ViewBuilder
    private var activityLoadingMoreSection: some View {
        if viewModel.isLoadingMore {
            Section {
                ExperienceIndeterminateProgress()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

}

private struct ActivityInboxRowListItem: View {
    let row: ActivityRowModel
    let colors: SemanticColorPalette
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void
    let onOpenActor: (ProfileID) -> Void
    let onDelete: () -> Void
    let onMarkRead: () -> Void
    let onMarkUnread: () -> Void
    let onAppear: () -> Void

    var body: some View {
        ActivityRowView(
            row: row,
            imagePipeline: imagePipeline,
            onSelect: onOpen,
            onSelectActor: row.usesTradeTraxsBrandAvatar
                ? nil
                : row.notification.actorProfileID.map { id in
                    { onOpenActor(id) }
                }
        )
        .onAppear(perform: onAppear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            if row.isUnread {
                Button(action: onMarkRead) {
                    Label("Mark as Read", systemImage: "envelope.open")
                }
                .tint(colors.info)
            }
        }
        .contextMenu {
            Button(action: onOpen) {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            if !row.usesTradeTraxsBrandAvatar,
               let actorID = row.notification.actorProfileID
            {
                Button {
                    onOpenActor(actorID)
                } label: {
                    Label("View Profile", systemImage: "person.crop.circle")
                }
            }
            if row.isUnread {
                Button(action: onMarkRead) {
                    Label("Mark as Read", systemImage: "envelope.open")
                }
            } else {
                Button(action: onMarkUnread) {
                    Label("Mark as Unread", systemImage: "envelope.badge")
                }
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        } preview: {
            ActivityRowView(
                row: row,
                imagePipeline: imagePipeline,
                onSelect: {},
                onSelectActor: nil
            )
            .frame(width: 320)
            .padding(.vertical, ExperienceSpacing.xs)
        }
    }
}
