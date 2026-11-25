import SwiftUI

/// Report detail section cards, dashboard chrome in light mode; legacy fill in dark.
struct ReportDetailSectionSurface: ViewModifier {
    var cornerRadius: CGFloat = ExperienceRadius.card

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        if colorScheme == .light {
            content.experienceDashboardCard(cornerRadius: cornerRadius)
        } else {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colors.fillSecondary.opacity(0.5))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(colors.border.opacity(0.45), lineWidth: ExperienceBorder.thin)
                    }
            }
        }
    }
}

struct YearlyReportHeroSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        if colorScheme == .light {
            content
                .background {
                    RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    colors.accent.opacity(0.14),
                                    colors.surfacePrimary,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                                .strokeBorder(
                                    colors.border.opacity(ExperienceDashboardSurface.LightChrome.borderOpacity),
                                    lineWidth: ExperienceBorder.hairline
                                )
                        }
                }
        } else {
            content.background {
                RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                colors.accent.opacity(0.14),
                                colors.fillSecondary.opacity(0.6),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }
}

struct ReportDetailInsetSurface: ViewModifier {
    var cornerRadius: CGFloat = ExperienceRadius.md

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        if colorScheme == .light {
            content.experienceDashboardNestedCard(cornerRadius: cornerRadius)
        } else {
            content.background(
                colors.fillSecondary.opacity(0.55),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

// MARK: - Key Metrics grid tiles

enum ReportKeyMetricsLayout {
    static let gridColumnSpacing = ExperienceSpacing.xs
    static let gridRowSpacing = ExperienceSpacing.xs
    static let tileCornerRadius = ExperienceRadius.sm
    static let tileContentPadding = ExperienceSpacing.sm
    static let tileLabelValueSpacing: CGFloat = 3
    /// Uniform tile height so paired columns stay aligned in the grid.
    static let tileHeight: CGFloat = 72

    static var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: gridColumnSpacing),
            GridItem(.flexible(), spacing: gridColumnSpacing),
        ]
    }
}

/// Nested metric tile inside the white Key Metrics section (light) or report card (dark).
struct ReportKeyMetricsTileChrome: ViewModifier {
    var cornerRadius: CGFloat = ReportKeyMetricsLayout.tileCornerRadius

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        if colorScheme == .light {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colors.elevatedSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                colors.border.opacity(0.45),
                                lineWidth: ExperienceBorder.hairline
                            )
                    }
            }
        } else {
            content.experienceDashboardNestedCard(cornerRadius: cornerRadius)
        }
    }
}

extension View {
    func reportKeyMetricsTile(cornerRadius: CGFloat = ReportKeyMetricsLayout.tileCornerRadius) -> some View {
        modifier(ReportKeyMetricsTileChrome(cornerRadius: cornerRadius))
    }

    func reportKeyMetricsTileFrame() -> some View {
        frame(
            maxWidth: .infinity,
            minHeight: ReportKeyMetricsLayout.tileHeight,
            maxHeight: ReportKeyMetricsLayout.tileHeight,
            alignment: .topLeading
        )
    }
}