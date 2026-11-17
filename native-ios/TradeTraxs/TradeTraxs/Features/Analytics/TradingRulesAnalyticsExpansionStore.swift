import SwiftUI

/// Persists analytics section expansion across navigation (UserDefaults only — no server writes).
@MainActor
@Observable
final class TradingRulesAnalyticsExpansionStore {
    static let shared = TradingRulesAnalyticsExpansionStore()

    private enum Key {
        static let worstDays = "tradingRules.analytics.expand.worstDays"
        static let recurring = "tradingRules.analytics.expand.recurring"
        static let trends = "tradingRules.analytics.expand.trends"
        static let ruleImpact = "tradingRules.analytics.expand.ruleImpact"
        static let violations = "tradingRules.analytics.expand.violations"
    }

    var worstTradingDaysExpanded: Bool {
        didSet { UserDefaults.standard.set(worstTradingDaysExpanded, forKey: Key.worstDays) }
    }
    var recurringPatternsExpanded: Bool {
        didSet { UserDefaults.standard.set(recurringPatternsExpanded, forKey: Key.recurring) }
    }
    var complianceTrendsExpanded: Bool {
        didSet { UserDefaults.standard.set(complianceTrendsExpanded, forKey: Key.trends) }
    }
    var ruleImpactExpanded: Bool {
        didSet { UserDefaults.standard.set(ruleImpactExpanded, forKey: Key.ruleImpact) }
    }
    var recentViolationsExpanded: Bool {
        didSet { UserDefaults.standard.set(recentViolationsExpanded, forKey: Key.violations) }
    }

    private init() {
        let defaults = UserDefaults.standard
        worstTradingDaysExpanded = defaults.object(forKey: Key.worstDays) as? Bool ?? true
        recurringPatternsExpanded = defaults.object(forKey: Key.recurring) as? Bool ?? true
        complianceTrendsExpanded = defaults.object(forKey: Key.trends) as? Bool ?? false
        ruleImpactExpanded = defaults.object(forKey: Key.ruleImpact) as? Bool ?? false
        recentViolationsExpanded = defaults.object(forKey: Key.violations) as? Bool ?? true
    }
}

struct TradingRulesAnalyticsCollapsibleSection<Content: View>: View {
    let title: String
    let infoTitle: String?
    let infoBody: String?
    let infoAccessibilityID: String?
    @Binding var isExpanded: Bool
  @ViewBuilder let content: () -> Content

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        isExpanded: Binding<Bool>,
        infoTitle: String? = nil,
        infoBody: String? = nil,
        infoAccessibilityID: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        _isExpanded = isExpanded
        self.infoTitle = infoTitle
        self.infoBody = infoBody
        self.infoAccessibilityID = infoAccessibilityID
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: ExperienceSpacing.sm) {
                    if let infoTitle, let infoBody {
                        AnalyticsSectionHeader(
                            title: title,
                            infoTitle: infoTitle,
                            infoBody: infoBody,
                            infoAccessibilityID: infoAccessibilityID
                        )
                    } else {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(colors.primaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(title), \(isExpanded ? "expanded" : "collapsed")")
            .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand")")

            if isExpanded {
                content()
            }
        }
    }
}
