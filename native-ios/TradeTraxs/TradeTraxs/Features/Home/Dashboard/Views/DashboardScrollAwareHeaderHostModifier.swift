import SwiftUI

/// Navigation bar + lifecycle hooks for Dashboard scroll-aware header (mirrors Feed home wiring).
struct DashboardScrollAwareHeaderHostModifier: ViewModifier {
    let reduceMotion: Bool
    let experimentActive: Bool
    let navigationBarVisibility: Visibility
    let homePathDepth: Int
    var categoryOverlayHidden: Bool = false
    @Binding var chromeHidden: Bool
    let onReset: () -> Void

    func body(content: Content) -> some View {
        content
            .toolbar(navigationBarVisibility, for: .navigationBar)
            .animation(
                reduceMotion ? nil : FeedScrollAwareHeaderExperiment.animation,
                value: chromeHidden
            )
            .onChange(of: homePathDepth) { _, depth in
                guard depth > 0 else { return }
                onReset()
            }
            .onChange(of: chromeHidden) { _, _ in
                #if DEBUG
                FeedScrollAwareHeaderDiagnostics.logChromeHiddenState(
                    chromeHidden: chromeHidden,
                    experimentActive: experimentActive,
                    navVisibility: navigationBarVisibility == .hidden ? "hidden" : "visible",
                    categoryOverlayHidden: categoryOverlayHidden
                )
                #endif
            }
            #if DEBUG
            .onAppear {
                FeedScrollAwareHeaderDiagnostics.logBootConfiguration()
            }
            .onChange(of: experimentActive) { _, active in
                FeedScrollAwareHeaderDiagnostics.logExperimentGateChange(
                    experimentActive: active,
                    isEnabled: FeedScrollAwareHeaderExperiment.dashboardScrollHeaderEnabled,
                    isClips: false,
                    feedPathDepth: homePathDepth
                )
            }
            #endif
    }
}
