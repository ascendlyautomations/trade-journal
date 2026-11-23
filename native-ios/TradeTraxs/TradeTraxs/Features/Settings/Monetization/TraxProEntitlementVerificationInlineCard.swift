import SwiftUI

/// Compact entitlement verification for dashboard premium sections.
struct TraxProEntitlementVerificationInlineCard: View {
    let profileID: ProfileID?
    var onRetry: () -> Void
    var accessibilityIdentifier: String = "entitlement.verification.inline"

    @Environment(\.themeColors) private var colors
    @State private var isRetrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.sm) {
                ProgressView()
                Text("Verifying your plan…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
            }
            Text("We're confirming TraxsPro access before showing advanced analytics.")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if profileID != nil {
                Button(isRetrying ? "Retrying…" : "Try Again") {
                    guard !isRetrying else { return }
                    isRetrying = true
                    onRetry()
                    Task {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        isRetrying = false
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.accent)
                .disabled(isRetrying)
                .accessibilityIdentifier("\(accessibilityIdentifier).retry")
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(prominence: .standard)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}