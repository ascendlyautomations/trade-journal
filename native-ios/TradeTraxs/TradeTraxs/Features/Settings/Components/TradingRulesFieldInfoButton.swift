import SwiftUI

struct TradingRulesFieldInfoButton: View {
    let info: TradingRulesFieldInfo
    @State private var showsInfo = false
    @Environment(\.themeColors) private var colors

    var body: some View {
        Button {
            showsInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(colors.tertiaryText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(info.title)")
        .accessibilityIdentifier("settings.tradingRules.info.\(info.rawValue)")
        .popover(isPresented: $showsInfo) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text(info.title)
                    .font(ExperienceTypography.subheadline.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                Text(info.body)
                    .font(ExperienceTypography.footnote)
                    .foregroundStyle(colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ExperienceSpacing.md)
            .frame(width: 280, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
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
