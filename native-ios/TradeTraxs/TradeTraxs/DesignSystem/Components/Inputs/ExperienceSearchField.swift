import SwiftUI

struct ExperienceSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var accessibilityIdentifier: String = "search.field"
    var cornerRadius: CGFloat = ExperienceRadius.md
    var showsSearchIcon: Bool = true
    var showsClearButton: Bool = true
    /// Trailing Cancel beside the field while focused or the query is non-empty (inline list search).
    var showsTrailingCancelWhenActive: Bool = false
    var isFocused: FocusState<Bool>.Binding? = nil
    var onCancel: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors

    private var showsCancel: Bool {
        guard showsTrailingCancelWhenActive else { return false }
        let focused = isFocused?.wrappedValue ?? false
        return focused || !text.isEmpty
    }

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            fieldChrome
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsCancel {
                Button("Cancel") {
                    ExperienceHaptics.play(.selection)
                    onCancel?()
                }
                .font(ExperienceTypography.body)
                .foregroundStyle(colors.accent)
                .buttonStyle(.experiencePlain)
                .experienceAccessibility(
                    label: "Cancel search",
                    identifier: "\(accessibilityIdentifier).cancel"
                )
            }
        }
    }

    @ViewBuilder
    private var fieldChrome: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            if showsSearchIcon {
                ExperienceIcon(icon: .search, size: .sm, color: colors.placeholder)
            }
            textField
            if showsClearButton, !text.isEmpty {
                ExperienceIconButton(icon: .close, accessibilityLabel: "Clear search") {
                    text = ""
                }
            }
        }
        .padding(.horizontal, showsSearchIcon ? ExperienceSpacing.sm : ExperienceSpacing.md)
        .padding(.vertical, showsSearchIcon ? ExperienceSpacing.xs : 10)
        .frame(minHeight: ExperienceAccessibility.minTouchTarget)
        .experienceFilterSearchField(cornerRadius: cornerRadius)
        .experienceAccessibility(label: placeholder, identifier: accessibilityIdentifier)
    }

    @ViewBuilder
    private var textField: some View {
        let field = TextField(placeholder, text: $text)
            .font(ExperienceTypography.body)
            .foregroundStyle(colors.primaryText)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
        if let isFocused {
            field.focused(isFocused)
        } else {
            field
        }
    }
}