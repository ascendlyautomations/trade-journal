import AuthenticationServices
import SwiftUI

struct SocialSignInButtons: View {
    var isEnabled: Bool
    var isLoading: Bool
    var onAppleCredential: (AppleIDCredentialPayload) -> Void
    var onAppleCancelled: () -> Void
    var onAppleFailure: (Error) -> Void
    var onGoogle: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentNonce: String?

    var body: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            SignInWithAppleButton(.continue) { request in
                guard isEnabled, !isLoading else { return }
                let nonce = AppleSignInNonce.generate()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = AppleSignInNonce.sha256Hex(nonce)
            } onCompletion: { result in
                handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(
                colorScheme == .dark ? .white : .black
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
            .disabled(!isEnabled || isLoading)
            .opacity(isEnabled && !isLoading ? ExperienceOpacity.opaque : ExperienceOpacity.disabled)
            .accessibilityIdentifier("auth.apple")

            socialButton(
                title: "Continue with Google",
                systemImage: "g.circle.fill",
                identifier: "auth.google",
                action: onGoogle
            )
        }
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard isEnabled, !isLoading else { return }
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                onAppleFailure(AuthenticationError.providerTokenInvalid(.apple))
                return
            }
            ExperienceHaptics.play(.selection)
            onAppleCredential(
                AppleIDCredentialPayload(
                    idToken: idToken,
                    nonce: currentNonce,
                    fullName: credential.fullName?.formattedDisplayName(),
                    email: ProfileDisplayNamePolicy.normalized(credential.email)
                )
            )
            currentNonce = nil

        case .failure(let error):
            currentNonce = nil
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                onAppleCancelled()
                return
            }
            onAppleFailure(error)
        }
    }

    private func socialButton(
        title: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isEnabled, !isLoading else { return }
            ExperienceHaptics.play(.selection)
            action()
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(ExperienceTypography.headline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
            .foregroundStyle(colors.primaryText)
            .background(colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                    .stroke(colors.border, lineWidth: ExperienceBorder.thin)
            }
            .opacity(isEnabled && !isLoading ? ExperienceOpacity.opaque : ExperienceOpacity.disabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
    }
}

struct AuthDivider: View {
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.md) {
            Rectangle()
                .fill(colors.separator)
                .frame(height: ExperienceBorder.thin)
            Text("or")
                .experienceStyle(.footnote, color: colors.secondaryText)
            Rectangle()
                .fill(colors.separator)
                .frame(height: ExperienceBorder.thin)
        }
        .accessibilityHidden(true)
    }
}
