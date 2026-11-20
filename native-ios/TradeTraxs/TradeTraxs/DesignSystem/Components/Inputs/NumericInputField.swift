import SwiftUI

/// Visible unit label beside a numeric field; values stay numeric in bindings/API.
enum NumericFieldAdornment: Sendable {
    case currencyPrefix
    case percentSuffix
}

struct NumericAdornedTextField: View {
    let placeholder: String
    @Binding var text: String
    /// When set, live comma/format rules apply on each edit. Omit when the binding already formats.
    var style: NumericInputStyle?
    var keyboard: UIKeyboardType = .decimalPad
    var adornment: NumericFieldAdornment

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.xxs) {
            if adornment == .currencyPrefix {
                Text("$")
                    .experienceStyle(.body, color: colors.secondaryText)
                    .accessibilityHidden(true)
            }
            numericTextField
                .keyboardType(keyboard)
            if adornment == .percentSuffix {
                Text("%")
                    .experienceStyle(.body, color: colors.secondaryText)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var numericTextField: some View {
        if let style {
            TextField(placeholder, text: $text.numericInput(style))
        } else {
            TextField(placeholder, text: $text)
        }
    }
}

extension Binding where Value == String {
    /// Applies live thousands-separator formatting on each edit.
    func numericInput(_ style: NumericInputStyle) -> Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                wrappedValue = NumericInputFieldSupport.formatWhileEditing(newValue, style: style)
            }
        )
    }
}
