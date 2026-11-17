import SwiftUI

/// Dropdown row chrome for the Trades filter sheet — elevated box in light mode; legacy fill in dark.
struct TradeHistoryFilterControlChrome: ViewModifier {
    enum Surface {
        /// Date / Session / Sort menus — dark keeps prior `fillSecondary` box.
        case dropdown
        /// Trades With Pictures — dark stays flush (no container).
        case toggleRow
    }

    var surface: Surface = .dropdown

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, surface == .toggleRow && colorScheme == .dark ? 0 : ExperienceSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: ExperienceSpacing.minTouchTarget, alignment: .leading)
            .background {
                if colorScheme == .light {
                    lightElevatedBackground
                } else if surface == .dropdown {
                    colors.fillSecondary
                        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
                }
            }
    }

    private var lightElevatedBackground: some View {
        RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
            .fill(colors.surfacePrimary)
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                    .strokeBorder(
                        colors.border.opacity(ExperienceTradingRulesSurface.lightBorderOpacity),
                        lineWidth: ExperienceBorder.hairline
                    )
            }
            .shadow(
                color: colors.surfaceOverlay.opacity(ExperienceTradingRulesSurface.lightShadowOpacity),
                radius: 6,
                x: 0,
                y: 2
            )
    }
}

extension View {
    func tradeHistoryFilterControlChrome(surface: TradeHistoryFilterControlChrome.Surface = .dropdown) -> some View {
        modifier(TradeHistoryFilterControlChrome(surface: surface))
    }
}

/// Menu-based filter dropdown — selected value left, chevron right.
struct TradeHistoryFilterDropdownMenu<MenuItems: View>: View {
    let selectionTitle: String
    var accessibilityLabel: String
    @ViewBuilder var menuItems: () -> MenuItems

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    private var chevronColor: Color {
        colorScheme == .light ? colors.secondaryText : colors.tertiaryText
    }

    var body: some View {
        Menu {
            menuItems()
        } label: {
            HStack(spacing: ExperienceSpacing.xs) {
                Text(selectionTitle)
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .fontWeight(colorScheme == .light ? .medium : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ExperienceIcon(icon: .chevronDown, size: .xs, color: chevronColor)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            .tradeHistoryFilterControlChrome()
            .contentShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selectionTitle)
    }
}