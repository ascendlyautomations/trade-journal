import SwiftUI

/// Shared dashboard / analytics / settings card chrome.
/// Light: elevated fill + hairline border + soft shadow.
/// Dark: opaque stepped surfaces + matching hairline borders (no flat translucency stack).
enum ExperienceDashboardSurface {
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

    enum DarkChrome {
        static let borderOpacity: CGFloat = 0.42
        static let insetBorderOpacity: CGFloat = 0.38
        static let controlBorderOpacity: CGFloat = 0.48
        static let featuredBorderOpacity: CGFloat = 0.55
        static let nestedBorderOpacity: CGFloat = 0.4
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
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: ExperienceBorder.hairline)
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
            switch prominence {
            case .standard:
                return colors.surfacePrimary
            case .featured:
                return colors.backgroundElevated
            }
        }
        return colors.surfacePrimary
    }

    private var borderColor: Color {
        if colorScheme == .light {
            switch prominence {
            case .standard:
                return colors.border.opacity(ExperienceDashboardSurface.LightChrome.borderOpacity)
            case .featured:
                return colors.borderStrong.opacity(ExperienceDashboardSurface.LightChrome.featuredBorderOpacity)
            }
        }
        switch prominence {
        case .standard:
            return colors.border.opacity(ExperienceDashboardSurface.DarkChrome.borderOpacity)
        case .featured:
            return colors.borderStrong.opacity(ExperienceDashboardSurface.DarkChrome.featuredBorderOpacity)
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
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(nestedBorderColor, lineWidth: ExperienceBorder.hairline)
                }
        }
    }

    private var nestedFill: Color {
        colors.fillPrimary
    }

    private var nestedBorderColor: Color {
        if colorScheme == .light {
            return colors.border.opacity(ExperienceDashboardSurface.LightChrome.insetBorderOpacity)
        }
        return colors.border.opacity(ExperienceDashboardSurface.DarkChrome.nestedBorderOpacity)
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

    // MARK: - Filter / dropdown / search controls

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
        content.background { controlBackground }
    }

    @ViewBuilder
    private var controlBackground: some View {
        switch shape {
        case .capsule:
            Capsule().fill(controlFill)
                .overlay {
                    Capsule()
                        .strokeBorder(controlBorder, lineWidth: ExperienceBorder.hairline)
                }
                .modifier(ControlShadowModifier(active: usesControlShadow))
        case .roundedRect(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(controlFill)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(controlBorder, lineWidth: ExperienceBorder.hairline)
                }
                .modifier(ControlShadowModifier(active: usesControlShadow))
        case .circle:
            Circle().fill(controlFill)
                .overlay {
                    Circle()
                        .strokeBorder(controlBorder, lineWidth: ExperienceBorder.hairline)
                }
        }
    }

    private var controlFill: Color {
        if colorScheme == .light {
            switch role {
            case .pageTrigger, .sheetRow:
                return colors.surfacePrimary
            case .insetField:
                return colors.fillPrimary
            }
        }
        switch role {
        case .pageTrigger, .sheetRow:
            return colors.surfaceSecondary
        case .insetField:
            return colors.fillPrimary
        }
    }

    private var controlBorder: Color {
        if colorScheme == .light {
            switch role {
            case .pageTrigger, .sheetRow:
                return colors.border.opacity(ExperienceDashboardSurface.LightChrome.controlBorderOpacity)
            case .insetField:
                return colors.border.opacity(ExperienceDashboardSurface.LightChrome.insetBorderOpacity)
            }
        }
        switch role {
        case .pageTrigger, .sheetRow:
            return colors.border.opacity(ExperienceDashboardSurface.DarkChrome.controlBorderOpacity)
        case .insetField:
            return colors.border.opacity(ExperienceDashboardSurface.DarkChrome.insetBorderOpacity)
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