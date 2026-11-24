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