import SwiftUI

extension View {
    /// Full-screen AI coach column — same background / expansion as ``ConversationView``.
    func aiCoachConversationRootChrome() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .experienceScreenBackground(fillsContentArea: false)
    }

    /// Message timeline scroll — interactive keyboard dismiss like DMs.
    func aiCoachConversationMessageScroll() -> some View {
        scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }
}

/// Filter strip pinned under the navigation bar (Feed filter bar chrome).
struct ExperiencePinnedAnalyticsFilterBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.themeColors) private var colors

    var body: some View {
        content()
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.sm)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.primaryBackground)
            .overlay(alignment: .bottom) {
                colors.separator.frame(height: ExperienceBorder.hairline)
            }
    }
}