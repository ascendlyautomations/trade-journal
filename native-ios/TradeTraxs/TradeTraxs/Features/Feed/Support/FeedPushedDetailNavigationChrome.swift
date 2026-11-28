import SwiftUI

/// Chevron-only back (no previous-screen title text). Same arrow styling and swipe-back as ``ExperienceArrowBackButton``.
struct ExperienceChevronOnlyBackNavigationChrome: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .experienceArrowBackToolbarButton(action: dismiss.callAsFunction)
            .navigationInteractivePopFromLeadingEdgeOnly()
    }
}

extension View {
    func experienceChevronOnlyBackNavigationChrome() -> some View {
        modifier(ExperienceChevronOnlyBackNavigationChrome())
    }

    /// Feed stack detail pushes, chevron-only back (no previous-screen "Feed" title).
    func feedPushedDetailNavigationChrome() -> some View {
        experienceChevronOnlyBackNavigationChrome()
    }

    @ViewBuilder
    func experienceChevronOnlyBackNavigationChrome(when enabled: Bool) -> some View {
        if enabled {
            experienceChevronOnlyBackNavigationChrome()
        } else {
            self
        }
    }
}
