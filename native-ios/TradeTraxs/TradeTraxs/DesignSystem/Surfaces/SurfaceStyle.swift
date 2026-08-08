import SwiftUI

enum SurfaceRole: Sendable {
    case primaryBackground
    case secondaryBackground
    case groupedBackground
    case card
    case elevatedCard
    case sheet
    case navigationBar
    case toolbar
    case tabBar
    case list
    case materialRegular
    case materialChrome
}

struct ExperienceSurfaceModifier: ViewModifier {
    let role: SurfaceRole
    var cornerRadius: CGFloat = 0
    var elevate: ElevationToken = .flat

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background { background }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .experienceElevation(elevate)
    }

    @ViewBuilder
    private var background: some View {
        switch role {
        case .primaryBackground:
            colors.primaryBackground
        case .secondaryBackground:
            colors.secondaryBackground
        case .groupedBackground, .list:
            colors.groupedBackground
        case .card:
            colors.cardBackground
        case .elevatedCard:
            colors.backgroundElevated
        case .sheet:
            if reduceTransparency {
                colors.sheetBackground
            } else {
                Rectangle().fill(ExperienceMaterials.sheet.material)
            }
        case .materialRegular:
            if reduceTransparency {
                colors.surfacePrimary
            } else {
                Rectangle().fill(ExperienceMaterials.sheet.material)
            }
        case .navigationBar, .toolbar:
            if reduceTransparency {
                colors.navigationBackground
            } else {
                Rectangle().fill(ExperienceMaterials.navBar.material)
            }
        case .tabBar, .materialChrome:
            if reduceTransparency {
                colors.tabBarBackground
            } else {
                Rectangle().fill(ExperienceMaterials.tabBar.material)
            }
        }
    }
}

extension View {
    func experienceSurface(
        _ role: SurfaceRole,
        cornerRadius: CGFloat = 0,
        elevation: ElevationToken = .flat
    ) -> some View {
        modifier(
            ExperienceSurfaceModifier(
                role: role,
                cornerRadius: cornerRadius,
                elevate: elevation
            )
        )
    }

    func experienceScreenBackground() -> some View {
        experienceSurface(.primaryBackground)
    }
}
