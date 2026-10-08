import SwiftUI

/// Dashboard-only A/B: opaque UIKit navigation bar (Feed-equivalent) during scroll-header testing.
///
/// Revert by setting ``matchesFeedOpaqueNavigationBar`` to `false`.
enum DashboardScrollHeaderOpaqueNavBarExperiment {
    static let matchesFeedOpaqueNavigationBar = true

    static func apply(active: Bool, colors: SemanticColorPalette) {
        guard ExperienceNavigationBarAppearance.dashboardScrollHeaderOpaqueNavBarActive != active else {
            return
        }
        ExperienceNavigationBarAppearance.dashboardScrollHeaderOpaqueNavBarActive = active
        ExperienceNavigationBarAppearance.syncShellBarChrome(colors: colors)
    }

    static func deactivate(colors: SemanticColorPalette) {
        apply(active: false, colors: colors)
    }
}

/// Applies opaque nav bar only while Dashboard root experiment gates are satisfied.
struct DashboardScrollHeaderOpaqueNavBarLifecycleModifier: ViewModifier {
    let experimentActive: Bool
    let colors: SemanticColorPalette

    func body(content: Content) -> some View {
        content
            .onChange(of: experimentActive, initial: true) { _, active in
                DashboardScrollHeaderOpaqueNavBarExperiment.apply(active: active, colors: colors)
            }
            .onDisappear {
                DashboardScrollHeaderOpaqueNavBarExperiment.deactivate(colors: colors)
            }
    }
}
