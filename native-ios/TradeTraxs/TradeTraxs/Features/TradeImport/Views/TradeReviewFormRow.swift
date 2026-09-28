import SwiftUI

/// Left label / right value (or control) row used on Review Trade and similar trade editors.
struct TradeReviewFormRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
            Text(label)
                .experienceStyle(.body, color: colors.secondaryText)
                .frame(minWidth: TradeReviewFormRowMetrics.labelWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            trailing()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .layoutPriority(0)
        }
    }
}

enum TradeReviewFormRowMetrics {
    /// Keeps labels aligned; long account names stay on the trailing side.
    static let labelWidth: CGFloat = 118

    static let rowInsets = EdgeInsets(
        top: ExperienceSpacing.xxs,
        leading: ExperienceSpacing.md,
        bottom: ExperienceSpacing.xxs,
        trailing: ExperienceSpacing.md
    )
}

extension View {
    func tradeReviewTrailingControlStyle() -> some View {
        multilineTextAlignment(.trailing)
            .font(ExperienceTypography.body)
    }
}
