import SwiftUI

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

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(colors.primaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            TradingRulesFieldInfoButton(info: info)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}