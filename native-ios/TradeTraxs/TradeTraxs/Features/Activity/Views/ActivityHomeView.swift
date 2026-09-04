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
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                if viewModel.sections.isEmpty {
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
                if viewModel.showsEmpty {
                    ExperienceEmptyState(
                        icon: .activity,
                        title: "No activity yet",
                        message: "When people interact with your trades, posts, profile, or Trade Rooms, you'll see it here."
                    )
                } else {
                    listContent
                }
            }
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
                }
                .accessibilityLabel("Activity options")
                .accessibilityIdentifier("activity.menu")
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .accessibilityIdentifier("activity.home")
    }

    private var listContent: some View {
        List {
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

            ForEach(viewModel.sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        ActivityRowView(
                            row: row,
                            imagePipeline: imagePipeline,
                            onSelect: { viewModel.open(row) },
                            onSelectActor: row.notification.actorProfileID.map { id in
                                { viewModel.openActor(id) }
                            }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(colors.backgroundPrimary)
                        .listRowSeparator(.hidden)
                        .onAppear {
                            viewModel.loadMoreIfNeeded(currentID: row.id)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if row.isUnread {
                                Button {
                                    viewModel.markRead(row: row)
                                } label: {
                                    Label("Read", systemImage: "envelope.open")
                                }
                                .tint(colors.info)
                            }
                        }
                        .contextMenu {
                            Button {
                                viewModel.open(row)
                            } label: {
                                Label("Open", systemImage: "arrow.up.right.square")
                            }
                            if row.isUnread {
                                Button {
                                    viewModel.markRead(row: row)
                                } label: {
                                    Label("Mark as Read", systemImage: "envelope.open")
                                }
                            }
                            if let actorID = row.notification.actorProfileID {
                                Button {
                                    viewModel.openActor(actorID)
                                } label: {
                                    Label("View Profile", systemImage: "person.crop.circle")
                                }
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
                } header: {
                    Text(section.section.rawValue)
                }
            }

            if viewModel.isLoadingMore {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}
