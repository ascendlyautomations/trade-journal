import SwiftUI

/// Comment-level like control — mirrors ``LikeButton`` styling.
struct CommentLikeButton: View {
    let snapshot: CommentLikeSnapshot
    let isEnabled: Bool
    let isBusy: Bool
    let onToggle: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button {
            guard isEnabled, !isBusy else { return }
            pulse = true
            onToggle()
            ExperienceMotion.withAnimation(ExperienceMotion.selection, reduceMotion: reduceMotion) {
                pulse = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: snapshot.liked ? "heart.fill" : "heart")
                    .symbolEffect(.bounce, value: pulse)
                    .foregroundStyle(snapshot.liked ? colors.error : colors.tertiaryText)
                    .scaleEffect(pulse ? 1.12 : 1)
                if snapshot.count > 0 {
                    Text(LikeButton.formatCount(snapshot.count))
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .contentTransition(.numericText())
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
        .opacity(isBusy ? 0.6 : 1)
        .accessibilityLabel(snapshot.liked ? "Unlike comment" : "Like comment")
        .accessibilityValue("\(snapshot.count)")
        .accessibilityIdentifier("interaction.comment.like")
    }
}
