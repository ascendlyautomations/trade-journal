import SwiftUI

/// Post-registration bootstrap chrome — matches auth launch branding, not storyboard splash.
struct CreatingAccountView: View {
    var failureMessage: String?
    var isRetrying: Bool = false
    var onRetry: (() -> Void)?

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    Spacer(minLength: ExperienceSpacing.xl)

                    logoBlock

                    Spacer(minLength: ExperienceSpacing.lg)
                }

                if let failureMessage {
                    bootstrapFailureOverlay(message: failureMessage, bottomInset: geometry.size.height * 0.35)
                } else {
                    progressBlock
                        .padding(.bottom, geometry.safeAreaInsets.bottom + geometry.size.height * 0.35)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .experienceScreenBackground()
        .accessibilityIdentifier("postSignup.creatingAccount.root")
    }

    private var logoBlock: some View {
        VStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)

            Text("TradeTraxs")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(colors.primaryText)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
    }

    private var progressBlock: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            Text("Creating Account...")
                .font(ExperienceTypography.callout)
                .fontWeight(.semibold)
                .foregroundStyle(colors.primaryText)
                .accessibilityIdentifier("postSignup.creatingAccount.title")

            ProgressView()
                .progressViewStyle(.circular)
                .tint(colors.secondaryText)
                .accessibilityLabel("Setting up your account")
        }
        .frame(maxWidth: .infinity)
    }

    private func bootstrapFailureOverlay(message: String, bottomInset: CGFloat) -> some View {
        VStack(spacing: ExperienceSpacing.md) {
            Text(message)
                .experienceStyle(.body, color: colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ExperienceSpacing.xl)
                .accessibilityIdentifier("postSignup.creatingAccount.failureMessage")

            if let onRetry {
                ExperienceButton(
                    title: isRetrying ? "Retrying…" : "Try Again",
                    kind: .primary,
                    isLoading: isRetrying,
                    action: onRetry
                )
                .disabled(isRetrying)
                .padding(.horizontal, ExperienceSpacing.xl)
                .accessibilityIdentifier("postSignup.creatingAccount.retry")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, bottomInset)
    }
}
