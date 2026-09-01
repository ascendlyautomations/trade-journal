import SwiftUI

struct FollowRequestsView: View {
    @State private var viewModel: FollowRequestsViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: FollowRequestsViewModel(
                followRequests: data.followRequests,
                notifications: data.notifications,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                inboxStore: .shared
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    init(viewModel: FollowRequestsViewModel, imagePipeline: any ImagePipeline) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                if viewModel.rows.isEmpty {
                    ExperienceListSkeleton(style: .personRow, rowCount: 6)
                } else {
                    listContent
                }
            case .failed(let message):
                if viewModel.rows.isEmpty {
                    ExperienceErrorState(
                        title: "Couldn't load requests",
                        message: message,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                } else {
                    listContent
                }
            case .loaded:
                if viewModel.showsEmpty {
                    ExperienceEmptyState(
                        icon: .profile,
                        title: "No follow requests",
                        message: "When someone requests to follow your private profile, they'll show up here."
                    )
                } else {
                    listContent
                }
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Follow Requests")
        .refreshable { await viewModel.refresh() }
        .task { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("activity.followRequests.home")
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.rows) { row in
                    HStack(spacing: ExperienceSpacing.sm) {
                        Button {
                            viewModel.openProfile(row.request.requesterProfileID)
                        } label: {
                            if let profile = row.profile {
                                FollowListAvatarView(
                                    profile: profile,
                                    imagePipeline: imagePipeline,
                                    size: 44
                                )
                            } else {
                                ExperienceAvatar(initials: "?", size: 44)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            viewModel.openProfile(row.request.requesterProfileID)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.profile?.displayName ?? "Trader")
                                    .experienceStyle(.body, color: colors.primaryText)
                                    .fontWeight(.semibold)
                                if let username = row.profile?.username {
                                    Text("@\(username)")
                                        .experienceStyle(.caption, color: colors.secondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Button("Confirm") {
                            viewModel.approve(row.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(row.isBusy)
                        .accessibilityIdentifier("activity.followRequests.confirm")

                        Button("Delete", role: .destructive) {
                            viewModel.decline(row.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(row.isBusy)
                        .accessibilityIdentifier("activity.followRequests.delete")
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.sm)

                    ExperienceDivider()
                        .padding(.leading, 72)
                }
            }
        }
    }
}
