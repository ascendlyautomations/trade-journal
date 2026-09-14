import SwiftUI

/// Shared focus identity for Login email/password (single ``FocusState`` owner in ``LoginView``).
enum AuthLoginField: Hashable {
    case email
    case password
}

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

    /// When set with ``loginFocusedField``, Login owns focus (no nested ``FocusState``).
    var loginField: AuthLoginField? = nil
    var loginFocusedField: FocusState<AuthLoginField?>.Binding? = nil

    @Environment(\.themeColors) private var colors
    @FocusState private var standaloneFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .experienceStyle(.caption, color: colors.secondaryText)

            HStack(spacing: ExperienceSpacing.xs) {
                inputField
                    .font(ExperienceTypography.body)
                    .foregroundStyle(colors.primaryText)
                    .submitLabel(submitLabel)
                    .onSubmit { onSubmit?() }

                if kind == .password || kind == .newPassword, let isSecureVisible {
                    Button {
                        if isFieldFocused {
                            if let loginFocusedField {
                                loginFocusedField.wrappedValue = nil
                            } else {
                                standaloneFocused = false
                            }
                            ExperienceKeyboard.dismiss()
                        }
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
                        isFieldFocused ? colors.accent : colors.border,
                        lineWidth: isFieldFocused ? ExperienceBorder.thick : ExperienceBorder.thin
                    )
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var inputField: some View {
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
        .id(inputFieldIdentity)
        .modifier(
            AuthTextFieldFocusModifier(
                loginField: loginField,
                loginFocusedField: loginFocusedField,
                standaloneFocused: $standaloneFocused
            )
        )
        .onChange(of: text) { old, new in
            guard old.isEmpty, !new.isEmpty, let loginField else { return }
            LoginFocusProbe.firstCharacterChanged(field: loginField.probeName)
        }
    }

    private var isFieldFocused: Bool {
        if let loginFocusedField, let loginField {
            return loginFocusedField.wrappedValue == loginField
        }
        return standaloneFocused
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

    /// Stable identity except when password visibility intentionally swaps SecureField ↔ TextField.
    private var inputFieldIdentity: String {
        if let loginField {
            switch loginField {
            case .email:
                return "auth.login.email"
            case .password:
                return showsSecureField ? "auth.login.password.secure" : "auth.login.password.visible"
            }
        }
        return "auth.field.\(title).\(kind)"
    }
}

/// Applies exactly one focus binding — Login enum or standalone bool (reset password, etc.).
private struct AuthTextFieldFocusModifier: ViewModifier {
    let loginField: AuthLoginField?
    let loginFocusedField: FocusState<AuthLoginField?>.Binding?
    @FocusState.Binding var standaloneFocused: Bool

    func body(content: Content) -> some View {
        if let loginFocusedField, let loginField {
            content.focused(loginFocusedField, equals: loginField)
        } else {
            content.focused($standaloneFocused)
        }
    }
}

extension AuthLoginField {
    fileprivate var probeName: String {
        switch self {
        case .email: return "email"
        case .password: return "password"
        }
    }
}
