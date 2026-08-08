import SwiftUI

struct ExperienceSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var accessibilityIdentifier: String = "search.field"

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            ExperienceIcon(icon: .search, size: .sm, color: colors.placeholder)
            TextField(placeholder, text: $text)
                .font(ExperienceTypography.body)
                .foregroundStyle(colors.primaryText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            if !text.isEmpty {
                ExperienceIconButton(icon: .close, accessibilityLabel: "Clear search") {
                    text = ""
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .frame(minHeight: ExperienceAccessibility.minTouchTarget)
        .background(colors.fillSecondary)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .experienceAccessibility(label: placeholder, identifier: accessibilityIdentifier)
    }
}
