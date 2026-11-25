import SwiftUI

/// Pins the comment composer above the keyboard for detail screens (composer outside the main scroll).
struct CommentsDetailChrome<Content: View>: View {
    let target: InteractionTarget
    let contentOwnerUserID: String?
    let data: DataEnvironment
    @ViewBuilder let content: (
        _ viewModel: CommentsViewModel,
        _ currentUserID: ProfileID?,
        _ viewerProfile: Profile?
    ) -> Content

    @State private var viewModel: CommentsViewModel
    @State private var currentUserID: ProfileID?
    @State private var viewerProfile: Profile?

    init(
        target: InteractionTarget,
        contentOwnerUserID: String? = nil,
        data: DataEnvironment,
        @ViewBuilder content: @escaping (
            _ viewModel: CommentsViewModel,
            _ currentUserID: ProfileID?,
            _ viewerProfile: Profile?
        ) -> Content
    ) {
        self.target = target
        self.contentOwnerUserID = contentOwnerUserID
        self.data = data
        self.content = content
        _viewModel = State(
            initialValue: CommentsViewModel(
                target: target,
                repository: data.interactions,
                engagementStore: data.engagementStore,
                session: data.session,
                contentOwnerUserID: contentOwnerUserID,
                detailCache: data.detailCache,
                realtimeHub: data.realtimeHub,
                trades: data.trades
            )
        )
    }

    var body: some View {
        content(viewModel, currentUserID, viewerProfile)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CommentComposerView(
                    viewModel: viewModel,
                    imagePipeline: data.imagePipeline
                )
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.xs)
                .background(colorsBackground)
            }
            .task {
                viewModel.loadIfNeeded()
                if let id = await data.session.currentUserID {
                    let profileID = ProfileID(id.rawValue)
                    currentUserID = profileID
                    viewerProfile = data.detailCache.profile(id: profileID)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .onDisappear {
                viewModel.stopCommentRealtime()
            }
    }

  @Environment(\.themeColors) private var colors

    private var colorsBackground: Color {
        colors.backgroundPrimary
    }
}