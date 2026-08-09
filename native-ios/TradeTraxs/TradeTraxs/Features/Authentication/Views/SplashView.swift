import SwiftUI

/// Branded cold-launch surface shown while session restore completes.
struct SplashView: View {
    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    colors.backgroundPrimary,
                    colors.backgroundSecondary,
                    colors.accentMuted.opacity(0.35),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: ExperienceSpacing.lg) {
                ZStack {
                    Circle()
                        .fill(colors.accent.opacity(0.16))
                        .frame(width: 108, height: 108)
                        .scaleEffect(appeared ? 1 : 0.86)

                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(colors.accent)
                        .opacity(appeared ? 1 : 0.7)
                }
                .accessibilityHidden(true)

                VStack(spacing: ExperienceSpacing.xs) {
                    Text("TradeTraxs")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(colors.primaryText)

                    Text("Your trading journal")
                        .experienceStyle(.subheadline, color: colors.secondaryText)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

                ProgressView()
                    .tint(colors.accent)
                    .padding(.top, ExperienceSpacing.xl)
                    .accessibilityLabel("Restoring session")
            }
        }
        .onAppear {
            ExperienceMotion.withAnimation(
                ExperienceMotion.navigation,
                reduceMotion: reduceMotion
            ) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("TradeTraxs is launching")
    }
}
