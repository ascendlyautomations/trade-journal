import SwiftUI

enum CommentThreadScrollIDs {
    static let threadBottom = "interaction.comment.thread.bottom"
}

/// Keeps newest comments visible while the keyboard stays open (detail scroll + reel sheet).
struct CommentThreadScrollModifier: ViewModifier {
    @Bindable var viewModel: CommentsViewModel
    let scrollProxy: ScrollViewProxy
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.scrollToThreadBottomToken) { _, _ in
                scrollToBottom(animated: true)
            }
            .onChange(of: viewModel.comments.count) { _, _ in
                guard viewModel.maintainKeyboardScrollAnchor else { return }
                scrollToBottom(animated: true)
            }
    }

    private func scrollToBottom(animated: Bool) {
        let animation = ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion)
        if animated {
            withAnimation(animation) {
                scrollProxy.scrollTo(CommentThreadScrollIDs.threadBottom, anchor: .bottom)
            }
        } else {
            scrollProxy.scrollTo(CommentThreadScrollIDs.threadBottom, anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            scrollProxy.scrollTo(CommentThreadScrollIDs.threadBottom, anchor: .bottom)
        }
    }
}

extension View {
    func commentThreadScrollSupport(
        viewModel: CommentsViewModel,
        scrollProxy: ScrollViewProxy,
        reduceMotion: Bool = false
    ) -> some View {
        modifier(
            CommentThreadScrollModifier(
                viewModel: viewModel,
                scrollProxy: scrollProxy,
                reduceMotion: reduceMotion
            )
        )
    }
}