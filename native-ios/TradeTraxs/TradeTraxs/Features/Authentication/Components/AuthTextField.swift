import SwiftUI

/// Native auth field with autofill + password-manager support.
struct AuthTextField: View {
    enum Kind {
        case email
        case password
        case newPassword
    }

    let title: String
    @Binding var text: String
    var kind: Kind = .email
    var isSecureVisible: Binding<Bool>? = nil
    var textContentType: UITextContentType? = nil
    var submitLabel: SubmitLabel = .next
    var onSubmit: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .experienceStyle(.caption, color: colors.secondaryText)

            HStack(spacing: ExperienceSpacing.xs) {
                Group {
                    if showsSecureField {
                        SecureField("", text: $text)
                            .textContentType(resolvedContentType)
                    } else {
                        TextField("", text: $text)
                            .textContentType(resolvedContentType)
                            .keyboardType(kind == .email ? .emailAddress : .default)
                            .textInputAutocapitalization(kind == .email ? .never : .sentences)
                            .autocorrectionDisabled(kind == .email)
                    }
                }
                .font(ExperienceTypography.body)
                .foregroundStyle(colors.primaryText)
                .focused($isFocused)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }

                if kind == .password || kind == .newPassword, let isSecureVisible {
                    Button {
                        ExperienceHaptics.play(.selection)
                        isSecureVisible.wrappedValue.toggle()
                    } label: {
                        Image(systemName: isSecureVisible.wrappedValue ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(colors.secondaryText)
                            .frame(
                                width: ExperienceAccessibility.minTouchTarget,
                                height: ExperienceAccessibility.minTouchTarget
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSecureVisible.wrappedValue ? "Hide password" : "Show password")
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
            .background(colors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                    .stroke(
                        isFocused ? colors.accent : colors.border,
                        lineWidth: isFocused ? ExperienceBorder.thick : ExperienceBorder.thin
                    )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var showsSecureField: Bool {
        switch kind {
        case .email:
            return false
        case .password, .newPassword:
            return !(isSecureVisible?.wrappedValue ?? false)
        }
    }

    private var resolvedContentType: UITextContentType? {
        if let textContentType { return textContentType }
        switch kind {
        case .email: return .username
        case .password: return .password
        case .newPassword: return .newPassword
        }
    }
}
