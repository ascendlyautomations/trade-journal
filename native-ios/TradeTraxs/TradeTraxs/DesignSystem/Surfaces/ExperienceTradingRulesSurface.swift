import SwiftUI

/// Card and control chrome for Trading Rules settings + analytics, delegates to shared dashboard card chrome.
enum ExperienceTradingRulesSurface {}

// MARK: - Cards

extension View {
    func experienceTradingRulesCard(
        prominence: ExperienceDashboardSurface.Prominence = .standard
    ) -> some View {
        experienceDashboardCard(prominence: prominence)
    }

    func experienceTradingRulesCard(cornerRadius: CGFloat) -> some View {
        experienceDashboardCard(cornerRadius: cornerRadius)
    }

    /// Value fields, scope menus, and compact pickers inside Trading Rules settings cards.
    func tradingRulesInsetControl() -> some View {
        modifier(TradingRulesInsetControlModifier())
    }

    /// Filter bar account / time / filters chips on Trading Rules Analytics.
    func tradingRulesFilterChip() -> some View {
        modifier(TradingRulesFilterChipModifier())
    }

    /// Nested block inside a category card (e.g. account overrides).
    func tradingRulesNestedGroup() -> some View {
        modifier(TradingRulesNestedGroupModifier())
    }
}

// MARK: - Nested controls (settings fields, filter chips)

private struct TradingRulesInsetControlModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.vertical, ExperienceSpacing.xs)
            .experienceFilterSearchField(cornerRadius: ExperienceRadius.sm)
    }
}

private struct TradingRulesFilterChipModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.experienceFilterCapsule()
    }
}

private struct TradingRulesNestedGroupModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, ExperienceSpacing.xxs)
            .experienceFilterSearchField(cornerRadius: ExperienceRadius.sm)
    }
}