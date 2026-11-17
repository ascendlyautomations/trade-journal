import SwiftUI

/// Card and control chrome for Trading Rules settings + analytics — stronger light-mode separation; dark unchanged.
enum ExperienceTradingRulesSurface {
    static let lightShadowOpacity: CGFloat = 0.07
    static let lightShadowRadius: CGFloat = 12
    static let lightShadowY: CGFloat = 4
    static let lightBorderOpacity: CGFloat = 0.9
    static let lightFeaturedBorderOpacity: CGFloat = 1
}

// MARK: - Cards

private struct ExperienceTradingRulesCardBackground: ViewModifier {
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat
    var prominence: ExperienceDashboardSurface.Prominence

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(cardFill)
                .overlay {
                    if colorScheme == .light {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: ExperienceBorder.hairline)
                    }
                }
                .shadow(
                    color: shadowColor,
                    radius: shadowRadius,
                    x: 0,
                    y: shadowY
                )
        }
    }

    private var cardFill: Color {
        if colorScheme == .dark {
            return colors.fillSecondary.opacity(ExperienceDashboardSurface.cardFillOpacity)
        }
        return colors.surfacePrimary
    }

    private var borderColor: Color {
        switch prominence {
        case .standard:
            return colors.border.opacity(ExperienceTradingRulesSurface.lightBorderOpacity)
        case .featured:
            return colors.borderStrong.opacity(ExperienceTradingRulesSurface.lightFeaturedBorderOpacity)
        }
    }

    private var shadowColor: Color {
        guard colorScheme == .light else { return .clear }
        return colors.surfaceOverlay.opacity(ExperienceTradingRulesSurface.lightShadowOpacity)
    }

    private var shadowRadius: CGFloat {
        colorScheme == .light ? ExperienceTradingRulesSurface.lightShadowRadius : 0
    }

    private var shadowY: CGFloat {
        colorScheme == .light ? ExperienceTradingRulesSurface.lightShadowY : 0
    }
}

// MARK: - Nested controls (settings fields, filter chips)

private struct TradingRulesInsetControlModifier: ViewModifier {
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .light {
            content
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, ExperienceSpacing.xs)
                .background(colors.fillPrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                        .strokeBorder(colors.border.opacity(0.72), lineWidth: ExperienceBorder.hairline)
                }
        } else {
            content
        }
    }
}

private struct TradingRulesFilterChipModifier: ViewModifier {
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .light {
            content
                .background(colors.fillPrimary, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(colors.border.opacity(0.75), lineWidth: ExperienceBorder.hairline)
                }
        } else {
            content
                .background(colors.fillSecondary, in: Capsule())
        }
    }
}

private struct TradingRulesNestedGroupModifier: ViewModifier {
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .light {
            content
                .background(colors.fillTertiary.opacity(0.65))
        } else {
            content
                .padding(.vertical, ExperienceSpacing.xxs)
                .background(colors.fillSecondary.opacity(0.45), in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        }
    }
}

extension View {
    func experienceTradingRulesCard(
        prominence: ExperienceDashboardSurface.Prominence = .standard
    ) -> some View {
        modifier(
            ExperienceTradingRulesCardBackground(
                cornerRadius: ExperienceDashboardSurface.cornerRadius(prominence),
                prominence: prominence
            )
        )
    }

    func experienceTradingRulesCard(cornerRadius: CGFloat) -> some View {
        modifier(
            ExperienceTradingRulesCardBackground(cornerRadius: cornerRadius, prominence: .standard)
        )
    }

    /// Value fields, scope menus, and compact pickers inside Trading Rules settings cards (light mode).
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