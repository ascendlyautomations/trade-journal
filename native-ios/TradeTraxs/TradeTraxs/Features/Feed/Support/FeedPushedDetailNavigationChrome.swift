import SwiftUI

/// Feed stack detail pushes — chevron-only back (no previous-screen "Feed" title).
struct FeedPushedDetailNavigationChrome: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .experienceArrowBackToolbarButton(action: dismiss.callAsFunction)
            .navigationInteractivePopFromLeadingEdgeOnly()
    }
}

extension View {
    func feedPushedDetailNavigationChrome() -> some View {
        modifier(FeedPushedDetailNavigationChrome())
    }
}
