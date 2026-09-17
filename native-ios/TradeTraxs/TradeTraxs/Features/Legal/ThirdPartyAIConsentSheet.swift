import SwiftUI

struct ThirdPartyAIConsentSheet: View {
    let onContinue: () -> Void
    let onNotNow: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    Text(
                        "TradeTraxs uses OpenAI to provide AI-powered analysis. When you use AI features, relevant trading information, notes, and other content you choose to analyze may be securely sent to OpenAI for processing."
                    )
                    .experienceStyle(.body, color: colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                    Button {
                        openURL(LegalDocuments.privacy)
                    } label: {
                        Text("Privacy Policy")
                            .experienceStyle(.body, color: colors.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("aiConsent.privacyPolicy")
                }
                .experiencePadding(.lg)
            }
            .experienceNavigationTitle("AI Data Processing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now", action: onNotNow)
                        .accessibilityIdentifier("aiConsent.notNow")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: onContinue)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("aiConsent.continue")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("aiConsent.sheet")
    }
}
