import SwiftUI

/// Detail-screen comments host — lazy loads on appear; content-type injected.
struct CommentsSectionView: View {
    @State private var viewModel: CommentsViewModel
    @State private var currentUserID: ProfileID?
    private let session: any SessionProviding
    private let imagePipeline: any ImagePipeline

    init(target: InteractionTarget, data: DataEnvironment) {
        _viewModel = State(
            initialValue: CommentsViewModel(
                target: target,
                repository: data.interactions,
                engagementStore: data.engagementStore,
                session: data.session,
                detailCache: data.detailCache
            )
        )
        self.session = data.session
        self.imagePipeline = data.imagePipeline
    }

    var body: some View {
        CommentListView(
            viewModel: viewModel,
            currentUserID: currentUserID,
            imagePipeline: imagePipeline
        )
            .task {
                viewModel.loadIfNeeded()
                if let id = await session.currentUserID {
                    currentUserID = ProfileID(id.rawValue)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
    }
}
