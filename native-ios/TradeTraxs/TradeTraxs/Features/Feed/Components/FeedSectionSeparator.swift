import SwiftUI

/// Full-width band separating consecutive feed timeline rows (All / Trades / Posts / Achievements).
struct FeedSectionSeparator: View {
    @Environment(\.themeColors) private var colors

    /// Visible section gap — thicker than a hairline, compact enough to avoid empty-card feel.
    static let height: CGFloat = 5

    var body: some View {
        Rectangle()
            .fill(colors.fillSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .accessibilityHidden(true)
    }
}
