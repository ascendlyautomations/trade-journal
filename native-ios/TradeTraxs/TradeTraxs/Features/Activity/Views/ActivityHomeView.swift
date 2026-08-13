import SwiftUI

struct ActivityHomeView: View {
    @State private var viewModel: ActivityHomeViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: ActivityHomeViewModel(
                notifications: data.notifications,
                followRequests: data.followRequests,
                profiles: data.profiles,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                realtimeHub: data.realtimeHub
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    init(viewModel: ActivityHomeViewModel, imagePipeline: any ImagePipeline) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                if viewModel.sections.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if viewModel.pendingFollowRequestCount > 0 {
                    ActivityFollowRequestsBanner(
                        count: viewModel.pendingFollowRequestCount,
                        action: { viewModel.openFollowRequests() }
                    )
                    ExperienceDivider()
                        .padding(.leading, ExperienceSpacing.md)
                }

                ForEach(viewModel.sections) { section in
                    Text(section.section.rawValue)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .fontWeight(.semibold)
                        .textCase(.uppercase)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.top, ExperienceSpacing.md)
                        .padding(.bottom, ExperienceSpacing.xs)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(section.rows) { row in
                        ActivityRowView(
                            row: row,
                            imagePipeline: imagePipeline,
                            onSelect: { viewModel.open(row) },
                            onSelectActor: row.notification.actorProfileID.map { id in
                                { viewModel.openActor(id) }
                            }
                        )
                        .onAppear {
                            viewModel.loadMoreIfNeeded(currentID: row.id)
                        }
                        ExperienceDivider()
                            .padding(.leading, 68)
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ExperienceSpacing.md)
                }
            }
        }
    }
}
