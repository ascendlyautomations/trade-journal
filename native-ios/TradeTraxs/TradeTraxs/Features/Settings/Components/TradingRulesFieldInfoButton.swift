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
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
            TradingRulesFieldInfoButton(info: info)
            Spacer(minLength: 0)
        }
    }
}