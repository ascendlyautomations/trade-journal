import SwiftUI

/// Shared spacing for Settings → Trading Rules rows (label + trailing control).
enum TradingPreferenceFormLayout {
    static let fieldStackSpacing: CGFloat = ExperienceSpacing.xs
    static let secondaryLineSpacing: CGFloat = 3
    static let rowColumnSpacing: CGFloat = ExperienceSpacing.sm
    static let valueControlWidth: CGFloat = 108
    /// Rule template menu — wider trailing column so placeholder text is not clipped.
    static let templateDropdownControlWidth: CGFloat = valueControlWidth * 1.25
}

extension View {
    /// Leading label column: grows within the card, wraps up to two lines.
    func tradingRulesSettingsLabelColumn(alignment: Alignment = .leading) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
            .layoutPriority(1)
    }

    /// Trailing control column: fixed width so the row never exceeds the card width.
    func tradingRulesSettingsValueColumn(
        width: CGFloat = TradingPreferenceFormLayout.valueControlWidth,
        alignment: Alignment = .trailing
    ) -> some View {
        frame(width: width, alignment: alignment)
            .layoutPriority(0)
    }

    func tradingRulesSettingsRow() -> some View {
        padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.xs + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}