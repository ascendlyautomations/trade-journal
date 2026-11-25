import SwiftUI

/// Detail-screen comments list (composer is pinned via ``CommentsDetailChrome`` or reel sheet chrome).
struct CommentsSectionView: View {
    @Bindable var viewModel: CommentsViewModel
    let currentUserID: ProfileID?
    let imagePipeline: any ImagePipeline

    var body: some View {
        CommentListView(
            viewModel: viewModel,
            currentUserID: currentUserID,
            imagePipeline: imagePipeline,
            presentation: .embeddedList
        )
    }
}