import SwiftUI

/// Shared Check-In History surfaces — stronger card structure in light mode; dark unchanged.
enum CheckInHistoryCardChrome {
    static let sectionCornerRadius = ExperienceRadius.md

    static func sectionFill(colors: SemanticColorPalette, colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return colors.surfacePrimary
        }
        return colors.surfacePrimary
    }

    enum SurfaceStyle {
        /// History list rows — border in dark and light (legacy dark appearance).
        case listRow
        /// Day detail sections — hairline border in light only.
        case detailSection
    }

    static func showsSectionBorder(colorScheme: ColorScheme, style: SurfaceStyle) -> Bool {
        switch style {
        case .listRow:
            return true
        case .detailSection:
            return colorScheme == .light
        }
    }

    static func sectionBorderOpacity(colorScheme: ColorScheme, style: SurfaceStyle) -> Double {
        switch style {
        case .listRow:
            return colorScheme == .light ? ExperienceOpacity.subtle : 1
        case .detailSection:
            return ExperienceOpacity.subtle
        }
    }

    static func rowDividerOpacity(colorScheme: ColorScheme) -> Double {
        colorScheme == .light ? 0.55 : 0.35
    }
}

private struct CheckInHistorySectionCard: ViewModifier {
    var style: CheckInHistoryCardChrome.SurfaceStyle

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                CheckInHistoryCardChrome.sectionFill(colors: colors, colorScheme: colorScheme),
                in: RoundedRectangle(
                    cornerRadius: CheckInHistoryCardChrome.sectionCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                if CheckInHistoryCardChrome.showsSectionBorder(colorScheme: colorScheme, style: style) {
                    RoundedRectangle(
                        cornerRadius: CheckInHistoryCardChrome.sectionCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(
                        colors.border.opacity(
                            CheckInHistoryCardChrome.sectionBorderOpacity(colorScheme: colorScheme, style: style)
                        ),
                        lineWidth: style == .listRow && colorScheme == .dark
                            ? 1
                            : ExperienceBorder.hairline
                    )
                }
            }
    }
}

extension View {
    func checkInHistorySectionCard(
        style: CheckInHistoryCardChrome.SurfaceStyle = .detailSection
    ) -> some View {
        modifier(CheckInHistorySectionCard(style: style))
    }
}