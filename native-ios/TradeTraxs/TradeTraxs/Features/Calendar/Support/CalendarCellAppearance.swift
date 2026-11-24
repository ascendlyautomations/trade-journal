import SwiftUI

/// Adaptive fills for calendar day / year month cells, stronger grid structure in light mode; dark unchanged.
enum CalendarCellAppearance {
    private static let darkNeutralFillOpacity = 0.35
    private static let darkOutcomeTintOpacity = 0.12

    private static let lightOutcomeTintOpacity = 0.14

    /// Opacity applied to out-of-month day cells (dark only, light mutes via fill).
    static func outsideMonthCellOpacity(colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.35 : 1
    }

    static func dayCellFill(
        colors: SemanticColorPalette,
        colorScheme: ColorScheme,
        isCurrentMonth: Bool,
        outcome: TradingDayOutcome?
    ) -> Color {
        if colorScheme == .dark {
            return darkDayCellFill(colors: colors, isCurrentMonth: isCurrentMonth, outcome: outcome)
        }
        return lightDayCellFill(colors: colors, isCurrentMonth: isCurrentMonth, outcome: outcome)
    }

    static func yearMonthCardFill(
        colors: SemanticColorPalette,
        colorScheme: ColorScheme,
        isNeutral: Bool,
        netPnL: Decimal
    ) -> Color {
        if colorScheme == .dark {
            return darkYearMonthFill(colors: colors, isNeutral: isNeutral, netPnL: netPnL)
        }
        return lightYearMonthFill(colors: colors, isNeutral: isNeutral, netPnL: netPnL)
    }

  // MARK: - Dark (legacy)

    private static func darkDayCellFill(
        colors: SemanticColorPalette,
        isCurrentMonth: Bool,
        outcome: TradingDayOutcome?
    ) -> Color {
        guard isCurrentMonth, let outcome, outcome != .none else {
            return colors.fillTertiary.opacity(darkNeutralFillOpacity)
        }
        return outcomeTint(colors: colors, outcome: outcome, opacity: darkOutcomeTintOpacity)
    }

    private static func darkYearMonthFill(
        colors: SemanticColorPalette,
        isNeutral: Bool,
        netPnL: Decimal
    ) -> Color {
        if isNeutral {
            return colors.fillTertiary.opacity(darkNeutralFillOpacity)
        }
        if netPnL > 0 { return colors.profit.opacity(darkOutcomeTintOpacity) }
        if netPnL < 0 { return colors.loss.opacity(darkOutcomeTintOpacity) }
        return colors.neutralMetric.opacity(darkOutcomeTintOpacity)
    }

  // MARK: - Light

    private static func lightDayCellFill(
        colors: SemanticColorPalette,
        isCurrentMonth: Bool,
        outcome: TradingDayOutcome?
    ) -> Color {
        if !isCurrentMonth {
            return colors.fillPrimary.opacity(0.55)
        }
        guard let outcome, outcome != .none else {
            return colors.surfaceSecondary
        }
        return outcomeTint(colors: colors, outcome: outcome, opacity: lightOutcomeTintOpacity)
    }

    private static func lightYearMonthFill(
        colors: SemanticColorPalette,
        isNeutral: Bool,
        netPnL: Decimal
    ) -> Color {
        if isNeutral {
            return colors.surfaceSecondary
        }
        if netPnL > 0 { return colors.profit.opacity(lightOutcomeTintOpacity) }
        if netPnL < 0 { return colors.loss.opacity(lightOutcomeTintOpacity) }
        return colors.neutralMetric.opacity(lightOutcomeTintOpacity)
    }

    private static func outcomeTint(
        colors: SemanticColorPalette,
        outcome: TradingDayOutcome,
        opacity: Double
    ) -> Color {
        switch outcome {
        case .profit:
            return colors.profit.opacity(opacity)
        case .loss:
            return colors.loss.opacity(opacity)
        case .breakeven:
            return colors.neutralMetric.opacity(opacity)
        case .none:
            return colors.fillTertiary.opacity(darkNeutralFillOpacity)
        }
    }
}