import SwiftUI
import UIKit

struct TradingRulesFieldInfoButton: View {
    let info: TradingRulesFieldInfo

    var body: some View {
        AnalyticsMetricInfoButton(
            title: info.title,
            bodyText: info.body,
            accessibilityID: "settings.tradingRules.info.\(info.rawValue)"
        )
    }
}

struct TradingRulesFieldLabel: View {
    let title: String
    let info: TradingRulesFieldInfo
    @Environment(\.themeColors) private var colors
    @Environment(\.sizeCategory) private var sizeCategory

    var body: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(colors.primaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            TradingRulesFieldInfoButton(info: info)
                .padding(.top, infoIconTopInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Centers the ⓘ control on the first text line (single- or multi-line labels).
    private var infoIconTopInset: CGFloat {
        _ = sizeCategory
        return TradingRulesFieldLabelMetrics.infoIconTopInset()
    }
}

private enum TradingRulesFieldLabelMetrics {
    /// Matches `AnalyticsMetricInfoButton` touch target.
    static let infoControlSize: CGFloat = 28

    static func infoIconTopInset() -> CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let firstLineMidpoint = font.lineHeight / 2
        return max(0, firstLineMidpoint - infoControlSize / 2)
    }
}