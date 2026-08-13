import SwiftUI

/// Production Followers / Following list — Instagram-style, TradeTraxs Experience chrome.
struct FollowListView: View {
    @State private var viewModel: FollowListViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        kind: FollowListKind,
        listOwnerID: ProfileID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: FollowListViewModel(
                kind: kind,
                listOwnerID: listOwnerID,
                profiles: data.profiles,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading where viewModel.items.isEmpty:
                skeleton
            case .failed(let message) where viewModel.items.isEmpty:
                ExperienceErrorState(
                    title: "Couldn't load \(viewModel.title.lowercased())",
                    message: message,
                    onRetry: { Task { await viewModel.refresh() } }
                )
            case .loaded where viewModel.showsEmpty:
                ExperienceEmptyState(
                    title: viewModel.kind.emptyTitle,
                    message: viewModel.kind.emptyMessage
                )
            default:
                listContent
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle(viewModel.title)
        .toolbar(.hidden, for: .tabBar)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: viewModel.kind.searchPlaceholder
        )
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .confirmationDialog(
            "Unfollow @\(viewModel.pendingUnfollow?.username ?? "")?",
            isPresented: Binding(
                get: { viewModel.pendingUnfollow != nil },
                set: { if !$0 { viewModel.pendingUnfollow = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Unfollow", role: .destructive) {
                Task { await viewModel.confirmUnfollow() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingUnfollow = nil
            }
        }
        .confirmationDialog(
            "Remove follower?",
            isPresented: Binding(
                get: { viewModel.pendingRemove != nil },
                set: { if !$0 { viewModel.pendingRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await viewModel.confirmRemove() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingRemove = nil
            }
        } message: {
            if let profile = viewModel.pendingRemove {
                Text("@\(profile.username) won’t be notified.")
            }
        }
        .accessibilityIdentifier("followList.\(viewModel.kind.rawValue)")
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.showsFilteredEmpty {
                    Text("No results for “\(viewModel.searchText)”")
                        .experienceStyle(.subheadline, color: colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ExperienceSpacing.xl)
                } else {
                    ForEach(viewModel.visibleItems) { profile in
                        FollowListRowView(
                            profile: profile,
                            imagePipeline: imagePipeline,
                            isFollowing: viewModel.isFollowing(profile),
                            showsRemove: viewModel.kind == .followers && viewModel.isOwnList,
                            onOpen: { viewModel.openProfile(profile) },
                            onToggleFollow: { viewModel.toggleFollow(for: profile) },
                            onRemove: { viewModel.requestRemove(profile) }
                        )
                        ExperienceDivider()
                            .padding(.leading, ExperienceSpacing.lg + 48 + ExperienceSpacing.md)
                    }
                }
            }
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: viewModel.visibleItems.map(\.id)
            )
        }
    }

    private var skeleton: some View {
        VStack(spacing: ExperienceSpacing.md) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: ExperienceSpacing.md) {
                    ExperienceSkeleton(height: 48, cornerRadius: 24)
                        .frame(width: 48)
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        ExperienceSkeleton(height: 14, cornerRadius: ExperienceRadius.xs)
                            .frame(width: 120)
                        ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                            .frame(width: 80)
                    }
                    Spacer()
                    ExperienceSkeleton(height: 32, cornerRadius: ExperienceRadius.button)
                        .frame(width: 88)
                }
                .padding(.horizontal, ExperienceSpacing.lg)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, ExperienceSpacing.md)
        .accessibilityIdentifier("followList.skeleton")
    }
}
