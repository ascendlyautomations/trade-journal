import SwiftUI

/// Active-story ring stroke — matches the Feed stories strip styling.
struct StoryAvatarRingStroke: View {
    /// When true, uses the gradient unread ring; otherwise a muted seen ring.
    var isHighlighted: Bool = true
    var diameter: CGFloat

    @Environment(\.themeColors) private var colors

    var body: some View {
        Group {
            if isHighlighted {
                Circle().stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.35, blue: 0.45),
                            Color(red: 0.96, green: 0.62, blue: 0.18),
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    lineWidth: lineWidth
                )
            } else {
                Circle()
                    .stroke(colors.border, lineWidth: 1)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var lineWidth: CGFloat {
        diameter >= 80 ? 3 : 2.5
    }

    /// Ring diameter for a circular avatar — tight padding matching the stories strip.
    static func ringDiameter(avatarSize: CGFloat) -> CGFloat {
        avatarSize + 10
    }
}
