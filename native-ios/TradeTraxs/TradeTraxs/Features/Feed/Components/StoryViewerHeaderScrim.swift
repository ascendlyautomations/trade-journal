import SwiftUI

/// Instagram-style top fade so story header stays readable on bright media. Non-interactive.
struct StoryViewerHeaderScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(StoryViewerChromeMetrics.headerScrimTopOpacity), location: 0),
                .init(color: Color.black.opacity(StoryViewerChromeMetrics.headerScrimMidOpacity), location: 0.42),
                .init(color: Color.black.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: StoryViewerChromeMetrics.headerScrimHeight)
        .padding(.top, -StoryViewerChromeMetrics.headerScrimTopBleed)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Subtle depth for white header labels and icons (no heavy outline).
    func storyViewerHeaderContrastShadow() -> some View {
        shadow(color: .black.opacity(0.38), radius: 3, x: 0, y: 1)
            .shadow(color: .black.opacity(0.22), radius: 1, x: 0, y: 0.5)
    }
}