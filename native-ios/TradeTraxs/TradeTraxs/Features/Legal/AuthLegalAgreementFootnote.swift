import SwiftUI

enum AuthLegalPresentation {
    /// Onboarding hero + Get Started (unchanged copy and layout).
    case onboarding
    /// Create Account — compact agreement directly above the primary button.
    case createAccountAgreement
    /// Standalone Terms / Privacy / Guidelines links (page footer).
    case footerLinks
}

/// Compact legal agreement copy for onboarding, login, and account creation.
struct AuthLegalAgreementFootnote: View {
    var presentation: AuthLegalPresentation = .onboarding

    @Environment(\.themeColors) private var colors
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch presentation {
        case .onboarding:
            onboardingContent
        case .createAccountAgreement:
            createAccountAgreementContent
        case .footerLinks:
            loginFooterLinksContent
        }
    }

    private var onboardingContent: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            Text(
                "By continuing, you agree to the Terms of Service and acknowledge the Privacy Policy and Community Guidelines."
            )
            .experienceStyle(.caption2, color: colors.tertiaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: ExperienceSpacing.sm) {
                onboardingLegalLink("Terms of Service", url: LegalDocuments.terms)
                Text("·")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                onboardingLegalLink("Privacy Policy", url: LegalDocuments.privacy)
                Text("·")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                onboardingLegalLink("Community Guidelines", url: LegalDocuments.communityGuidelines)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("auth.legalAgreement")
    }

    private var createAccountAgreementContent: some View {
        createAccountAgreementMarkdownText
            .font(ExperienceTypography.footnote)
            .foregroundStyle(colors.secondaryText)
            .tint(colors.accent)
            .multilineTextAlignment(.leading)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("auth.legalAgreement.createAccount")
    }

    private var createAccountAgreementMarkdownText: Text {
        let terms = LegalDocuments.terms.absoluteString
        let privacy = LegalDocuments.privacy.absoluteString
        let guidelines = LegalDocuments.communityGuidelines.absoluteString
        return Text(
            .init(
                "By continuing, you agree to the [Terms of Service](\(terms)), [Privacy Policy](\(privacy)), and [Community Guidelines](\(guidelines))."
            )
        )
    }

    private var loginFooterLinksContent: some View {
        VStack(spacing: ExperienceSpacing.xxs) {
            HStack(spacing: ExperienceSpacing.sm) {
                loginFooterLegalLink("Terms of Service", url: LegalDocuments.terms)
                Text("·")
                    .font(ExperienceTypography.footnote)
                    .foregroundStyle(colors.secondaryText)
                loginFooterLegalLink("Privacy Policy", url: LegalDocuments.privacy)
            }
            loginFooterLegalLink("Community Guidelines", url: LegalDocuments.communityGuidelines)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("auth.legal.footer")
    }

    private func onboardingLegalLink(_ title: String, url: URL) -> some View {
        Button(title) {
            openURL(url)
        }
        .font(.caption2)
        .foregroundStyle(colors.accent)
    }

    private func loginFooterLegalLink(_ title: String, url: URL) -> some View {
        Button(title) {
            openURL(url)
        }
        .font(ExperienceTypography.footnote)
        .foregroundStyle(colors.accent)
    }
}
