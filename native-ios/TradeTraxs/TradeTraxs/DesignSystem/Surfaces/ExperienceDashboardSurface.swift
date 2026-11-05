import SwiftUI

/// Shared dashboard card chrome — matches inset-grouped row composite (`fillSecondary` at 35% over page).
enum ExperienceDashboardSurface {
    static let cardFillOpacity: CGFloat = 0.35

    enum Prominence {
        /// KPI strips, chart insets, insight tiles, performance tiles.
        case standard
        /// Primary dashboard cards (e.g. scorecard home).
        case featured
    }

    static func cornerRadius(_ prominence: Prominence) -> CGFloat {
        switch prominence {
        case .standard: ExperienceRadius.md
        case .featured: ExperienceRadius.lg
        }
    }
}

private struct ExperienceDashboardCardBackground: ViewModifier {
    @Environment(\.themeColors) private var colors
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background(
            colors.fillSecondary.opacity(ExperienceDashboardSurface.cardFillOpacity),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

extension View {
    func experienceDashboardCard(
        prominence: ExperienceDashboardSurface.Prominence = .standard
    ) -> some View {
        modifier(
            ExperienceDashboardCardBackground(
                cornerRadius: ExperienceDashboardSurface.cornerRadius(prominence)
            )
        )
    }

    func experienceDashboardCard(cornerRadius: CGFloat) -> some View {
        modifier(ExperienceDashboardCardBackground(cornerRadius: cornerRadius))
    }
}
