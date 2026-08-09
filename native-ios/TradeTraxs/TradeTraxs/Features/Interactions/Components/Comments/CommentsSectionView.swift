import SwiftUI

/// Detail-screen comments host — lazy loads on appear; content-type injected.
struct CommentsSectionView: View {
    @State private var viewModel: CommentsViewModel
    @State private var currentUserID: ProfileID?
    private let session: any SessionProviding

    init(target: InteractionTarget, data: DataEnvironment) {
        _viewModel = State(
            initialValue: CommentsViewModel(
                target: target,
                repository: data.interactions,
                engagementStore: data.engagementStore,
                session: data.session
            )
        )
        self.session = data.session
    }

    var body: some View {
        CommentListView(viewModel: viewModel, currentUserID: currentUserID)
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
