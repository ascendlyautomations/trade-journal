import SwiftUI

/// Full-screen launch image shown while session restore / bootstrap resolves.
///
/// Matches ``LaunchScreen.storyboard`` — same `LaunchScreen` asset, `scaleAspectFill`,
/// edge-to-edge (including safe areas). No spinner or overlaid branding.
struct SplashView: View {
    /// Storyboard launch background — visible only if the image fails to load.
    private static let launchBackground = Color(
        red: 0.043137254901960784,
        green: 0.12156862745098039,
        blue: 0.22745098039215686
    )

    var body: some View {
        Self.launchBackground
            .ignoresSafeArea()
            .overlay {
                Image("LaunchScreen")
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            }
            .clipped()
            .ignoresSafeArea()
            .accessibilityLabel("TradeTraxs is launching")
    }
}
