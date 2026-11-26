import SwiftUI

struct GroupConversationMembersView: View {
    @State private var viewModel: GroupConversationMembersViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @Bindable private var followCoordinator = FollowMutationCoordinator.shared

    init(
        conversation: Conversation,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator?,
        onOpenProfile: @escaping (ProfileID) -> Void
    ) {
        _viewModel = State(
            initialValue: GroupConversationMembersViewModel(
                conversation: conversation,
                profiles: data.profiles,
                session: data.session,
                detailCache: data.detailCache,
                onOpenProfile: onOpenProfile
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    var body: some View {
        let _ = followCoordinator.revision
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                ExperienceLoadingSpinner(label: "Loading members")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ExperienceErrorState(
                    title: "Couldn't load members",
                    message: message,
                    onRetry: { viewModel.loadIfNeeded() }
                )
            case .loaded:
                membersList
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Members")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("groupMembers.sheet")
    }

    private var membersList: some View {
        List {
            ForEach(viewModel.members) { profile in
                FollowListRowView(
                    profile: profile,
                    viewerProfileID: viewModel.viewerID,
                    imagePipeline: imagePipeline,
                    followButtonRevision: followCoordinator.revision,
                    isFollowing: viewModel.isFollowing(profile),
                    showsFollowControl: profile.id != viewModel.viewerID,
                    showsRemove: false,
                    onOpen: { viewModel.openProfile(profile) },
                    onToggleFollow: { viewModel.toggleFollow(profile) },
                    onRemove: {}
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(colors.backgroundPrimary)
            }
        }
        .experiencePlainListStyle()
    }
}

@Observable
@MainActor
final class GroupConversationMembersViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var members: [Profile] = []
    private(set) var viewerID: ProfileID?
    private let conversation: Conversation
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let onOpenProfile: (ProfileID) -> Void

    init(
        conversation: Conversation,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        onOpenProfile: @escaping (ProfileID) -> Void
    ) {
        self.conversation = conversation
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.onOpenProfile = onOpenProfile
    }

    func loadIfNeeded() {
        guard phase == .idle else { return }
        phase = .loading
        Task { await load() }
    }

    func openProfile(_ profile: Profile) {
        ExperienceHaptics.play(.selection)
        onOpenProfile(profile.id)
    }

    func isFollowing(_ profile: Profile) -> Bool {
        guard let viewerID else { return false }
        return FollowMutationCoordinator.shared.isFollowing(viewer: viewerID, target: profile.id)
    }

    func toggleFollow(_ profile: Profile) {
        guard let viewerID, profile.id != viewerID else { return }
        let following = isFollowing(profile)
        ExperienceHaptics.play(.selection)
        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewerID,
            target: profile.id,
            isFollowing: !following
        )
        Task {
            do {
                if following {
                    try await profiles.unfollow(from: viewerID, to: profile.id)
                } else {
                    try await profiles.follow(from: viewerID, to: profile.id)
                }
            } catch {
                FollowMutationCoordinator.shared.applyEdgeChange(
                    viewer: viewerID,
                    target: profile.id,
                    isFollowing: following
                )
            }
        }
    }

    private func load() async {
        viewerID = await session.currentUserID.map { ProfileID($0.rawValue) }
        var resolved: [Profile] = conversation.participantProfileIDs.compactMap { detailCache.profile(id: $0) }
        let missing = conversation.participantProfileIDs.filter { id in !resolved.contains(where: { $0.id == id }) }
        for id in missing {
            if let profile = try? await profiles.profile(id: id) {
                detailCache.seed(profile)
                resolved.append(profile)
            }
        }
        members = resolved.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        phase = .loaded
    }
}