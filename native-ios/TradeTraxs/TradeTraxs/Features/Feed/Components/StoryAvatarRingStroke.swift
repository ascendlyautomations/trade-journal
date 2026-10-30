import SwiftUI

/// Active-story ring stroke — matches the Feed stories strip styling.
struct StoryAvatarRingStroke: View {
    /// TradeTraxs active-story ring — light blue → light green (not IG pink/orange).
    static let activeRingGradient: [Color] = [
        Color(red: 0.45, green: 0.78, blue: 0.98),
        Color(red: 0.52, green: 0.92, blue: 0.65),
    ]

    /// When true, uses the gradient unread ring; otherwise a muted seen ring.
    var isHighlighted: Bool = true
    var diameter: CGFloat

    @Environment(\.themeColors) private var colors

    var body: some View {
        Group {
            if isHighlighted {
                Circle().stroke(
                    LinearGradient(
                        colors: Self.activeRingGradient,
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
