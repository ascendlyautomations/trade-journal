import SwiftUI

/// Dashboard insight copy — uses shared ``ExperienceExpandableText`` (2-line collapse + inline more/less).
struct DashboardExpandableInsightText: View {
    let text: String
    var typography: TypographyRole = .caption
    var textColor: Color?
    var lineLimit: Int = 2
    var accessibilityIdentifier: String?

    var body: some View {
        ExperienceExpandableText(
            text: text,
            typography: typography,
            textColor: textColor,
            collapsedLineLimit: lineLimit,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}