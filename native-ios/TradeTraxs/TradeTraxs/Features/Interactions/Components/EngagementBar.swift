import SwiftUI

/// Compact like + comment row for cards and detail headers.
struct EngagementBar: View {
    let target: InteractionTarget
    @Bindable var store: EngagementStore
    var onCommentTap: () -> Void

    var body: some View {
        HStack(spacing: ExperienceSpacing.md) {
            LikeButton(target: target, store: store)
            CommentButton(target: target, store: store, action: onCommentTap)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("interaction.bar.\(target.kind.rawValue).\(target.id)")
    }
}
