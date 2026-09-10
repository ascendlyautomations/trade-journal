import SwiftUI

enum ComplianceDisclaimerCopy {
    /// Shared App Store–safe financial/education disclaimer (Terms § No Financial Advice).
    static let financialEducation =
        "TradeTraxs provides journaling, analytics, and educational information only. It is not financial or investment advice. Past performance does not guarantee future results."

    static let tradeAI =
        "\(financialEducation) AI-generated insights may be inaccurate."

    static let psychologyCoach =
        "Coach responses are AI-generated, may contain mistakes, and are for educational and informational purposes only — not financial or investment advice."

    static let leaderboard =
        "\(financialEducation) Rankings reflect in-app activity only."

    static let performanceReport = financialEducation

    static let screenshotAI =
        "AI extraction may be inaccurate. Review all fields before importing."

    static let psychologyReportAI =
        "This AI summary may be inaccurate and is for educational purposes only — not financial or investment advice."

    static let termsURL = LegalDocuments.terms
}

/// Compact footnote for App Store–safe AI and performance disclaimers.
struct ComplianceDisclaimerFootnote: View {
    let text: String
    var showsTermsLink: Bool = false

    @Environment(\.themeColors) private var colors
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            if showsTermsLink {
                Button("Terms") {
                    openURL(LegalDocuments.terms)
                }
                .font(.caption2)
                .foregroundStyle(colors.accent)
                .accessibilityIdentifier("compliance.disclaimer.terms")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("compliance.disclaimer")
    }
}
