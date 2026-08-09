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
                if !reduceMotion {
                    withAnimation(ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: false)) {
                        pulse = false
                    }
                } else {
                    pulse = false
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: snap.viewerHasLiked ? "heart.fill" : "heart")
                    .symbolEffect(.bounce, value: pulse)
                    .foregroundStyle(snap.viewerHasLiked ? colors.error : colors.secondaryText)
                    .scaleEffect(pulse ? 1.15 : 1)
                Text(Self.formatCount(snap.likeCount))
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .contentTransition(.numericText())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(snap.viewerHasLiked ? "Unlike" : "Like")
        .accessibilityValue("\(snap.likeCount)")
        .accessibilityIdentifier("interaction.like.\(target.kind.rawValue).\(target.id)")
    }

    static func formatCount(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
}
