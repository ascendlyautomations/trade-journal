import AuthenticationServices
import OSLog
import SwiftUI

struct SocialSignInButtons: View {
    var isEnabled: Bool
    var isLoading: Bool
    var onAppleInteractionBegan: () -> Void
    var onAppleCredential: (AppleIDCredentialPayload) -> Void
    var onAppleCancelled: () -> Void
    var onAppleFailure: (Error) -> Void
    var onGoogleInteractionBegan: () -> Void
    var onGoogle: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentNonce: String?

    private var socialButtonHeight: CGFloat { ExperienceAccessibility.minTouchTarget }

    var body: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            SignInWithAppleButton(.continue) { request in
                guard isEnabled, !isLoading else { return }
                onAppleInteractionBegan()
                ExperienceKeyboard.dismiss()
#if DEBUG
                AppLog.authentication.debug("[AppleAuth] credential.request.started")
#endif
                let nonce = AppleSignInNonce.generate()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = AppleSignInNonce.sha256Hex(nonce)
            } onCompletion: { result in
                handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: socialButtonHeight)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
            .overlay {
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                        .stroke(colors.borderStrong, lineWidth: ExperienceBorder.thin)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
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
            guard isEnabled else { return }
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
#if DEBUG
                AppLog.authentication.debug(
                    "[AppleAuth] credential.request.failed reason=missingIdentityToken identityToken.present=false authorizationCode.present=\((authorization.credential as? ASAuthorizationAppleIDCredential)?.authorizationCode != nil, privacy: .public)"
                )
#endif
                onAppleFailure(AuthenticationError.providerTokenInvalid(.apple))
                return
            }
#if DEBUG
            AppLog.authentication.debug(
                "[AppleAuth] credential.request.succeeded identityToken.present=true authorizationCode.present=\(credential.authorizationCode != nil, privacy: .public) nonce.present=\(currentNonce != nil, privacy: .public)"
            )
#endif
            guard let nonce = currentNonce, !nonce.isEmpty else {
                onAppleFailure(AuthenticationError.providerTokenInvalid(.apple))
                return
            }
            ExperienceHaptics.play(.selection)
            let authorizationCode = credential.authorizationCode.flatMap {
                String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            onAppleCredential(
                AppleIDCredentialPayload(
                    idToken: idToken,
                    nonce: nonce,
                    authorizationCode: authorizationCode?.isEmpty == false ? authorizationCode : nil,
                    fullName: credential.fullName?.formattedDisplayName(),
                    email: ProfileDisplayNamePolicy.normalized(credential.email)
                )
            )
            currentNonce = nil

        case .failure(let error):
            currentNonce = nil
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
#if DEBUG
                AppLog.authentication.debug("[AppleAuth] credential.request.cancelled")
#endif
                onAppleCancelled()
                return
            }
#if DEBUG
            AppLog.authentication.debug(
                "[AppleAuth] credential.request.failed errorType=\(String(describing: type(of: error)), privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
#endif
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
            if identifier == "auth.google" {
                onGoogleInteractionBegan()
            }
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
            .frame(height: socialButtonHeight)
            .foregroundStyle(colors.primaryText)
            .background(colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                    .stroke(
                        colorScheme == .light ? colors.borderStrong : colors.border,
                        lineWidth: ExperienceBorder.thin
                    )
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
            Text("OR")
                .experienceStyle(.footnote, color: colors.secondaryText)
            Rectangle()
                .fill(colors.separator)
                .frame(height: ExperienceBorder.thin)
        }
        .accessibilityHidden(true)
    }
}
