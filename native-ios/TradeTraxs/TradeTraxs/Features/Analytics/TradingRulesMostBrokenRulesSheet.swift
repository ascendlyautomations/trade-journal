import SwiftUI

struct TradingRulesMostBrokenRulesSheet: View {
    let rules: [TradingRulesViolationPatterns.MostBrokenRuleRow]
    var onOpenRule: ((TradingRulesComplianceAnalytics.RuleID) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ExperienceSpacing.xs) {
                    ForEach(rules) { row in
                        Button {
                            dismiss()
                            onOpenRule?(row.ruleID)
                        } label: {
                            HStack(spacing: ExperienceSpacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.ruleLabel)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(colors.primaryText)
                                    Text("\(row.violated) violations · \(row.evaluated) checks")
                                        .experienceStyle(.caption2, color: colors.secondaryText)
                                }
                                Spacer(minLength: 0)
                                if let rate = row.violationRatePercent {
                                    Text("\(rate, specifier: "%.1f")%")
                                        .font(.subheadline.weight(.bold).monospacedDigit())
                                        .foregroundStyle(colors.loss)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(colors.tertiaryText)
                            }
                            .padding(ExperienceSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .experienceTradingRulesCard(prominence: .standard)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(ExperienceSpacing.md)
            }
            .experienceScreenBackground()
            .experienceNavigationTitle("Most broken rules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .experienceSheetChrome()
    }
}
