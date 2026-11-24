import SwiftUI

/// Shared dashboard / analytics / settings card chrome, cool lift in dark mode;
/// light mode uses elevated fill + hairline border + soft shadow (dark unchanged).
enum ExperienceDashboardSurface {
    static let cardFillOpacity: CGFloat = 0.35

    enum Prominence {
        /// KPI strips, chart insets, insight tiles, performance tiles.
        case standard
        /// Primary dashboard cards (e.g. scorecard home).
        case featured
    }

    enum LightChrome {
        static let borderOpacity: CGFloat = 0.72
        static let insetBorderOpacity: CGFloat = 0.55
        static let controlBorderOpacity: CGFloat = 0.75
        static let featuredBorderOpacity: CGFloat = 0.88
        static let shadowOpacity: CGFloat = 0.07
        static let controlShadowOpacity: CGFloat = 0.06
        static let shadowRadius: CGFloat = 10
        static let controlShadowRadius: CGFloat = 6
        static let shadowY: CGFloat = 3
        static let controlShadowY: CGFloat = 2
    }

    static func cornerRadius(_ prominence: Prominence) -> CGFloat {
        switch prominence {
        case .standard: ExperienceRadius.md
        case .featured: ExperienceRadius.lg
        }
    }
}

// MARK: - Primary grouped cards

private struct ExperienceDashboardCardBackground: ViewModifier {
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
            return colors.border.opacity(ExperienceDashboardSurface.LightChrome.borderOpacity)
        case .featured:
            return colors.borderStrong.opacity(ExperienceDashboardSurface.LightChrome.featuredBorderOpacity)
        }
    }

    private var shadowColor: Color {
        guard colorScheme == .light else { return .clear }
        return colors.surfaceOverlay.opacity(ExperienceDashboardSurface.LightChrome.shadowOpacity)
    }

    private var shadowRadius: CGFloat {
        colorScheme == .light ? ExperienceDashboardSurface.LightChrome.shadowRadius : 0
    }

    private var shadowY: CGFloat {
        colorScheme == .light ? ExperienceDashboardSurface.LightChrome.shadowY : 0
    }
}

// MARK: - Nested tiles inside cards (stat chips, metric tiles)

private struct ExperienceDashboardNestedCardBackground: ViewModifier {
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(nestedFill)
                .overlay {
                    if colorScheme == .light {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                colors.border.opacity(0.55),
                                lineWidth: ExperienceBorder.hairline
                            )
                    }
                }
        }
    }

    private var nestedFill: Color {
        if colorScheme == .dark {
            return colors.fillSecondary.opacity(ExperienceDashboardSurface.cardFillOpacity)
        }
        return colors.fillPrimary
    }
}

// MARK: - Plain grouped panel (scorecard sections, report blocks)

private struct ExperienceGroupedPanelBackground: ViewModifier {
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat
    var prominence: ExperienceDashboardSurface.Prominence

    func body(content: Content) -> some View {
        content
            .modifier(
                ExperienceDashboardCardBackground(
                    cornerRadius: cornerRadius,
                    prominence: prominence
                )
            )
    }
}

extension View {
    func experienceDashboardCard(
        prominence: ExperienceDashboardSurface.Prominence = .standard
    ) -> some View {
        modifier(
            ExperienceDashboardCardBackground(
                cornerRadius: ExperienceDashboardSurface.cornerRadius(prominence),
                prominence: prominence
            )
        )
    }

    func experienceDashboardCard(cornerRadius: CGFloat) -> some View {
        modifier(
            ExperienceDashboardCardBackground(cornerRadius: cornerRadius, prominence: .standard)
        )
    }

    /// Nested stat / metric tile inside a dashboard or scorecard card.
    func experienceDashboardNestedCard(cornerRadius: CGFloat = ExperienceRadius.sm) -> some View {
        modifier(ExperienceDashboardNestedCardBackground(cornerRadius: cornerRadius))
    }

    /// Full-width grouped panel on the page canvas (scorecard, analytics sections).
    func experienceGroupedPanel(
        cornerRadius: CGFloat = ExperienceRadius.lg,
        prominence: ExperienceDashboardSurface.Prominence = .featured
    ) -> some View {
        modifier(
            ExperienceGroupedPanelBackground(cornerRadius: cornerRadius, prominence: prominence)
        )
    }

    // MARK: - Filter / dropdown / search controls (light elevated chrome; dark legacy fills)

    /// Capsule filter triggers (account, scope, leaderboard chips) on the page canvas.
    func experienceFilterCapsule(elevated: Bool = false) -> some View {
        modifier(
            ExperienceFilterControlChrome(
                shape: .capsule,
                role: .pageTrigger,
                elevated: elevated
            )
        )
    }

    /// Rounded menu row inside filter sheets (dashboard scope, share pickers).
    func experienceFilterMenuRow(cornerRadius: CGFloat = ExperienceRadius.sm) -> some View {
        modifier(
            ExperienceFilterControlChrome(
                shape: .roundedRect(cornerRadius),
                role: .sheetRow,
                elevated: true
            )
        )
    }

    /// Circular icon control (dashboard tool buttons, calendar chrome).
    func experienceFilterIconCircle() -> some View {
        modifier(
            ExperienceFilterControlChrome(
                shape: .circle,
                role: .pageTrigger,
                elevated: false
            )
        )
    }

    /// Search field and dense inset fields on the page canvas.
    func experienceFilterSearchField(cornerRadius: CGFloat = ExperienceRadius.md) -> some View {
        modifier(
            ExperienceFilterControlChrome(
                shape: .roundedRect(cornerRadius),
                role: .insetField,
                elevated: false
            )
        )
    }

    /// Unselected segment-style chip (non-capsule rect).
    func experienceFilterChipRect(cornerRadius: CGFloat = ExperienceRadius.sm) -> some View {
        modifier(
            ExperienceFilterControlChrome(
                shape: .roundedRect(cornerRadius),
                role: .pageTrigger,
                elevated: false
            )
        )
    }
}

// MARK: - Shared filter / menu control chrome

enum ExperienceFilterControlChromeRole {
    /// White control on page background (filter capsules, dropdown triggers).
    case pageTrigger
    /// White control row in sheets (dropdown-style elevation).
    case sheetRow
    /// Neutral inset fill inside cards or for search.
    case insetField
}

private enum ExperienceFilterControlShape {
    case capsule
    case roundedRect(CGFloat)
    case circle
}

private struct ExperienceFilterControlChrome: ViewModifier {
    var shape: ExperienceFilterControlShape
    var role: ExperienceFilterControlChromeRole
    var elevated: Bool

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .light {
            content.background { lightBackground }
        } else {
            content.background { darkBackground }
        }
    }

    @ViewBuilder
    private var lightBackground: some View {
        switch shape {
        case .capsule:
            Capsule().fill(lightFill)
                .overlay {
                    Capsule()
                        .strokeBorder(lightBorder, lineWidth: ExperienceBorder.hairline)
                }
                .modifier(ControlShadowModifier(active: usesControlShadow))
        case .roundedRect(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(lightFill)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(lightBorder, lineWidth: ExperienceBorder.hairline)
                }
                .modifier(ControlShadowModifier(active: usesControlShadow))
        case .circle:
            Circle().fill(lightFill)
                .overlay {
                    Circle()
                        .strokeBorder(lightBorder, lineWidth: ExperienceBorder.hairline)
                }
        }
    }

    @ViewBuilder
    private var darkBackground: some View {
        switch shape {
        case .capsule:
            Capsule().fill(colors.fillSecondary)
        case .roundedRect(let radius):
            colors.fillSecondary
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        case .circle:
            Circle().fill(colors.fillSecondary)
        }
    }

    private var lightFill: Color {
        switch role {
        case .pageTrigger, .sheetRow:
            return colors.surfacePrimary
        case .insetField:
            return colors.fillPrimary
        }
    }

    private var lightBorder: Color {
        switch role {
        case .pageTrigger, .sheetRow:
            return colors.border.opacity(ExperienceDashboardSurface.LightChrome.controlBorderOpacity)
        case .insetField:
            return colors.border.opacity(ExperienceDashboardSurface.LightChrome.insetBorderOpacity)
        }
    }

    private var usesControlShadow: Bool {
        guard colorScheme == .light else { return false }
        if role == .sheetRow { return true }
        return elevated
    }
}

private struct ControlShadowModifier: ViewModifier {
    var active: Bool
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        if active {
            content.shadow(
                color: colors.surfaceOverlay.opacity(ExperienceDashboardSurface.LightChrome.controlShadowOpacity),
                radius: ExperienceDashboardSurface.LightChrome.controlShadowRadius,
                x: 0,
                y: ExperienceDashboardSurface.LightChrome.controlShadowY
            )
        } else {
            content
        }
    }
}