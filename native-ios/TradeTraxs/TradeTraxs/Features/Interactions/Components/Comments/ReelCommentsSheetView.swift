import SwiftUI

/// Reels/TikTok-style comments sheet, reuses ``CommentsViewModel`` and comment row UI.
struct ReelCommentsSheetView: View {
    let target: InteractionTarget
    let contentOwnerUserID: String
    let data: DataEnvironment
    let imagePipeline: any ImagePipeline

    @State private var viewModel: CommentsViewModel
    @State private var currentUserID: ProfileID?
    @Environment(\.themeColors) private var colors

    init(
        target: InteractionTarget,
        contentOwnerUserID: String,
        data: DataEnvironment,
        imagePipeline: any ImagePipeline
    ) {
        self.target = target
        self.contentOwnerUserID = contentOwnerUserID
        self.data = data
        self.imagePipeline = imagePipeline
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
        VStack(spacing: 0) {
            Text("Comments")
                .font(.headline.weight(.semibold))
                .foregroundStyle(colors.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, ExperienceSpacing.sm)
                .padding(.bottom, ExperienceSpacing.xs)
                .accessibilityAddTraits(.isHeader)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    CommentListView(
                        viewModel: viewModel,
                        currentUserID: currentUserID,
                        imagePipeline: imagePipeline,
                        presentation: .sheetScrollContent
                    )
                    .padding(.horizontal, ExperienceSpacing.lg)
                    .padding(.vertical, ExperienceSpacing.sm)
                }
                .scrollDismissesKeyboard(.interactively)
                .commentThreadScrollSupport(
                    viewModel: viewModel,
                    scrollProxy: proxy
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(colors.backgroundPrimary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                CommentComposerView(
                    viewModel: viewModel,
                    imagePipeline: imagePipeline
                )
                .padding(.horizontal, ExperienceSpacing.lg)
                .padding(.vertical, ExperienceSpacing.sm)
                .background(colors.backgroundPrimary)
            }
        }
        .task {
            viewModel.loadIfNeeded()
            if let id = await data.session.currentUserID {
                currentUserID = ProfileID(id.rawValue)
            }
        }
        .onDisappear {
            viewModel.stopCommentRealtime()
        }
        .accessibilityIdentifier("feed.clips.commentsSheet")
    }
}
