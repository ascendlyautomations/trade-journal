import SwiftUI

/// Production Followers / Following list, Instagram-style, TradeTraxs Experience chrome.
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
        @Bindable var viewModel = viewModel
        Group {
            switch viewModel.phase {
            case .idle where viewModel.items.isEmpty, .loading where viewModel.items.isEmpty:
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
                guard let profile = viewModel.pendingUnfollow else { return }
                viewModel.pendingUnfollow = nil
                Task { await viewModel.confirmUnfollow(profile) }
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
                guard let profile = viewModel.pendingRemove else { return }
                FollowListRemoveDiagnostics.confirmInvoked(
                    followerID: profile.id.rawValue,
                    ownerID: viewModel.listOwnerID.rawValue
                )
                viewModel.pendingRemove = nil
                Task { await viewModel.confirmRemove(profile) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingRemove = nil
            }
        } message: {
            if let profile = viewModel.pendingRemove {
                Text("@\(profile.username) won’t be notified.")
            }
        }
        .alert(
            "Couldn't remove follower",
            isPresented: Binding(
                get: { viewModel.removeFollowerErrorMessage != nil },
                set: { if !$0 { viewModel.removeFollowerErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.removeFollowerErrorMessage = nil
            }
        } message: {
            if let message = viewModel.removeFollowerErrorMessage {
                Text(message)
            }
        }
        .accessibilityIdentifier("followList.\(viewModel.kind.rawValue)")
    }

    @ViewBuilder
    private var listContent: some View {
        if viewModel.kind == .followers {
            followersScrollContent
        } else {
            followingTableContent
        }
    }

    private var followersScrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.showsFilteredEmpty {
                    Text("No results for “\(viewModel.searchText)”")
                        .experienceStyle(.subheadline, color: colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ExperienceSpacing.xl)
                } else {
                    ForEach(viewModel.visibleItems, id: \.id) { profile in
                        followListRow(profile: profile, showsSwipeRemove: false)
                            .onAppear {
                                if viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    viewModel.loadMoreIfNeeded(currentProfileID: profile.id)
                                }
                            }
                    }
                }
            }
        }
        .background(colors.backgroundPrimary)
    }

    private var followingTableContent: some View {
        List {
            if viewModel.showsFilteredEmpty {
                Text("No results for “\(viewModel.searchText)”")
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ExperienceSpacing.xl)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.visibleItems, id: \.id) { profile in
                    followListRow(profile: profile, showsSwipeRemove: true)
                        .onAppear {
                            if viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                viewModel.loadMoreIfNeeded(currentProfileID: profile.id)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(colors.backgroundPrimary)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .experiencePlainListStyle()
    }

    @ViewBuilder
    private func followListRow(profile: Profile, showsSwipeRemove: Bool) -> some View {
        let row = FollowListRowView(
            profile: profile,
            viewerProfileID: viewModel.authenticatedProfileID,
            imagePipeline: imagePipeline,
            followButtonRevision: viewModel.followRevision,
            isFollowing: viewModel.isFollowing(profile),
            showsRemove: viewModel.kind == .followers && viewModel.isOwnList,
            onOpen: { viewModel.openProfile(profile) },
            onToggleFollow: { viewModel.toggleFollow(for: profile) },
            onRemove: { viewModel.requestRemove(profile) }
        )
        .opacity(viewModel.isRemoveInFlight(for: profile) ? 0.55 : 1)
        .allowsHitTesting(!viewModel.isRemoveInFlight(for: profile))
        .contextMenu {
            followListContextMenu(profile: profile)
        } preview: {
            FollowListRowView(
                profile: profile,
                viewerProfileID: viewModel.authenticatedProfileID,
                imagePipeline: imagePipeline,
                followButtonRevision: viewModel.followRevision,
                isFollowing: viewModel.isFollowing(profile),
                showsRemove: false,
                onOpen: {},
                onToggleFollow: {},
                onRemove: {}
            )
            .frame(width: 320)
        }

        if showsSwipeRemove {
            row.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if viewModel.kind == .following,
                   profile.id != viewModel.authenticatedProfileID,
                   viewModel.isFollowing(profile)
                {
                    Button(role: .destructive) {
                        viewModel.toggleFollow(for: profile)
                    } label: {
                        Label("Unfollow", systemImage: "person.badge.minus")
                    }
                }
            }
        } else {
            row
        }
    }

    @ViewBuilder
    private func followListContextMenu(profile: Profile) -> some View {
        Button {
            viewModel.openProfile(profile)
        } label: {
            Label("View Profile", systemImage: "person.crop.circle")
        }
        Button {
            _ = ExperienceClipboard.copy("@\(profile.username)")
            ExperienceHaptics.play(.success)
        } label: {
            Label("Copy Username", systemImage: "doc.on.doc")
        }
        if profile.id != viewModel.authenticatedProfileID {
            if viewModel.isFollowing(profile) {
                Button(role: .destructive) {
                    viewModel.toggleFollow(for: profile)
                } label: {
                    Label("Unfollow", systemImage: "person.badge.minus")
                }
            } else {
                Button {
                    viewModel.toggleFollow(for: profile)
                } label: {
                    Label("Follow", systemImage: "person.badge.plus")
                }
            }
        }
        if viewModel.kind == .followers && viewModel.isOwnList {
            Divider()
            Button(role: .destructive) {
                viewModel.requestRemove(profile)
            } label: {
                Label("Remove Follower", systemImage: "person.badge.minus")
            }
            .disabled(viewModel.isRemoveInFlight(for: profile))
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
