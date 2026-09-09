import SwiftUI

/// Reusable like control — content type injected via ``InteractionTarget``.
struct LikeButton: View {
    let target: InteractionTarget
    @Bindable var store: EngagementStore

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var snap: EngagementSnapshot { store.snapshot(for: target) }

    var body: some View {
        Button {
            pulse = true
            Task {
                await store.toggleLike(on: target)
                ExperienceMotion.withAnimation(ExperienceMotion.selection, reduceMotion: reduceMotion) {
                    pulse = false
                }
            }
        } label: {
            EngagementActionRowLabel(
                kind: .like(liked: snap.viewerHasLiked),
                count: snap.likeCount,
                iconColor: snap.viewerHasLiked ? colors.error : colors.secondaryText,
                iconScale: pulse ? 1.15 : 1,
                symbolBounce: pulse
            )
        }
        .buttonStyle(.plain)
        .engagementActionRowContainer()
        .accessibilityLabel(snap.viewerHasLiked ? "Unlike" : "Like")
        .accessibilityValue("\(snap.likeCount)")
        .accessibilityIdentifier("interaction.like.\(target.kind.rawValue).\(target.id)")
    }

    static func formatCount(_ value: Int) -> String {
        NumberDisplay.compactEngagementCount(value)
    }
}
