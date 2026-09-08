import SwiftUI

/// Reusable share affordance — matches ``LikeButton`` / ``CommentButton`` chrome.
struct ShareButton: View {
    var action: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: {
            ExperienceHaptics.play(.selection)
            action()
        }) {
            EngagementActionRowLabel(
                kind: .share,
                showsCount: false,
                iconColor: colors.secondaryText
            )
        }
        .buttonStyle(.plain)
        .engagementActionRowContainer()
        .accessibilityLabel("Share")
        .accessibilityIdentifier("interaction.share")
    }
}
