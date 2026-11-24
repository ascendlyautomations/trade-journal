import SwiftUI

/// Shown while TraxsPro entitlement is unknown, avoids fail-open premium access when enforcement is on.
struct TraxProEntitlementVerificationView: View {
    let profileID: ProfileID?
    var onRetry: (() -> Void)?

    @Environment(\.themeColors) private var colors
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: ExperienceSpacing.md) {
            ProgressView()
                .controlSize(.large)
            Text("Verifying your plan…")
                .experienceStyle(.headline, color: colors.primaryText)
            Text("We couldn't confirm TraxsPro access yet. This usually takes a moment.")
                .experienceStyle(.subheadline, color: colors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let onRetry {
                ExperienceButton(
                    title: isRetrying ? "Retrying…" : "Try Again",
                    kind: .primary,
                    isEnabled: !isRetrying && profileID != nil,
                    isLoading: isRetrying
                ) {
                    isRetrying = true
                    onRetry()
                    Task {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        isRetrying = false
                    }
                }
            }
        }
        .experiencePadding(.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .experienceScreenBackground()
        .accessibilityIdentifier("entitlement.verification")
    }
}