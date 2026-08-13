import SwiftUI

/// App-wide safe-area ownership for navigation + tab chrome.
///
/// Rule:
/// - Bar **backgrounds** extend to the physical screen edges (through safe areas).
/// - Interactive bar **controls** remain laid out by the system inside safe areas.
/// - Page content is inset exactly once by NavigationStack / TabView — never manually
///   re-padded with device-specific status-bar / home-indicator constants.
struct ExperienceAppChromeModifier: ViewModifier {
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        content
            .toolbarBackground(colors.navigationBackground, for: .navigationBar)
            .toolbarBackground(colors.tabBarBackground, for: .tabBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar, .tabBar)
            .modifier(ExperienceScrollEdgeChromeModifier())
    }
}

/// Prefer a hard scroll-edge treatment under system bars (iOS 26+), so content does not
/// rely on floating glass + automatic soft fade as a substitute for real bar backgrounds.
private struct ExperienceScrollEdgeChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.hard, for: [.top, .bottom])
        } else {
            content
        }
    }
}

/// Screen fill that reaches physical edges without moving interactive content.
struct ExperienceScreenBackgroundModifier: ViewModifier {
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        content.background {
            colors.primaryBackground
                .ignoresSafeArea()
        }
    }
}

extension View {
    /// Apply once at the authenticated shell (``MainTabShellView``).
    func experienceAppChrome() -> some View {
        modifier(ExperienceAppChromeModifier())
    }

    /// Page fill behind NavigationStack content — background ignores safe areas;
    /// the content itself stays system-inset.
    func experienceScreenBackground() -> some View {
        modifier(ExperienceScreenBackgroundModifier())
    }
}
