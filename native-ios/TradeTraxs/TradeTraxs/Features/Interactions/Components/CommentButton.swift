import SwiftUI

/// Reusable comment affordance — opens detail / focuses composer via `action`.
struct CommentButton: View {
    let target: InteractionTarget
    @Bindable var store: EngagementStore
    var action: () -> Void

    @Environment(\.themeColors) private var colors

    private var count: Int { store.snapshot(for: target).commentCount }

    var body: some View {
        Button(action: {
            ExperienceHaptics.play(.selection)
            action()
        }) {
            EngagementActionRowLabel(
                kind: .comment,
                count: count,
                iconColor: colors.secondaryText
            )
        }
        .buttonStyle(.plain)
        .engagementActionRowContainer()
        .accessibilityLabel("Comments")
        .accessibilityValue("\(count)")
        .accessibilityIdentifier("interaction.comment.\(target.kind.rawValue).\(target.id)")
    }
}
