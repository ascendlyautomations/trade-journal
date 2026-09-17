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
            .experienceKeyboardDismissOnTapOutside()
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
    var fillsContentArea: Bool
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        Group {
            if fillsContentArea {
                content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                content.frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background {
            colors.primaryBackground
                .ignoresSafeArea()
        }
    }
}

/// Minimum body fill for compact empty/loading states embedded in a parent ``ScrollView`` (Profile tabs).
struct ExperienceScrollEmbeddedSectionFillModifier: ViewModifier {
    var minHeight: CGFloat
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
            .background(colors.primaryBackground)
    }
}

extension View {
    /// Apply once at the authenticated shell (``MainTabShellView``).
    func experienceAppChrome() -> some View {
        modifier(ExperienceAppChromeModifier())
    }

    /// Page fill behind NavigationStack content — background ignores safe areas;
    /// the content itself stays system-inset.
    func experienceScreenBackground(fillsContentArea: Bool = true) -> some View {
        modifier(ExperienceScreenBackgroundModifier(fillsContentArea: fillsContentArea))
    }

    /// Expands placeholder content to the navigation content area (same treatment as Messages empty).
    func experienceScreenContentAreaFill(alignment: Alignment = .top) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    func experienceScrollEmbeddedSectionFill(minHeight: CGFloat = 440) -> some View {
        modifier(ExperienceScrollEmbeddedSectionFillModifier(minHeight: minHeight))
    }

    /// Opaque Feed navigation chrome while the vertical Clips pager scrolls.
    func experienceFeedClipsChrome(isActive: Bool) -> some View {
        modifier(FeedClipsChromeModifier(isActive: isActive))
    }
}

/// Keeps Feed nav/filter regions opaque while Clips video scrolls underneath.
private struct FeedClipsChromeModifier: ViewModifier {
    var isActive: Bool
    @Environment(\.themeColors) private var colors

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content
                .toolbarBackground(colors.navigationBackground, for: .navigationBar)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        } else {
            content
        }
    }
}
