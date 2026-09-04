import SwiftUI

/// Compact legal agreement copy for onboarding and account creation.
struct AuthLegalAgreementFootnote: View {
    @Environment(\.themeColors) private var colors
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            Text(
                "By continuing, you agree to the Terms of Service and acknowledge the Privacy Policy and Community Guidelines."
            )
            .experienceStyle(.caption2, color: colors.tertiaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: ExperienceSpacing.sm) {
                legalLink("Terms of Service", url: LegalDocuments.terms)
                Text("·")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                legalLink("Privacy Policy", url: LegalDocuments.privacy)
                Text("·")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                legalLink("Community Guidelines", url: LegalDocuments.communityGuidelines)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("auth.legalAgreement")
    }

    private func legalLink(_ title: String, url: URL) -> some View {
        Button(title) {
            openURL(url)
        }
        .font(.caption2)
        .foregroundStyle(colors.accent)
    }
}
