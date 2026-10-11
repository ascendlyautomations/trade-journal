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
    @State private var appleCredentialDeliveredForCurrentAuthorization = false

    private var socialButtonHeight: CGFloat { ExperienceAccessibility.minTouchTarget }

    var body: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            SignInWithAppleButton(.continue) { request in
                guard isEnabled, !isLoading else { return }
                appleCredentialDeliveredForCurrentAuthorization = false
                onAppleInteractionBegan()
                ExperienceKeyboard.dismiss()
#if DEBUG
                AppLog.authentication.debug("[AppleAuth] authorizationStarted")
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
            AppleAuthReleaseTrace.authorizationCompleted(outcome: "success")
            let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential
            let idToken = appleCredential?.identityToken.flatMap { String(data: $0, encoding: .utf8) }
            let authorizationCode = appleCredential?.authorizationCode.flatMap {
                String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let route = SocialSignInAppleCompletionRouting.routeSuccessfulAuthorization(
                idToken: idToken,
                rawNonce: currentNonce,
                authorizationCode: authorizationCode,
                fullName: appleCredential?.fullName?.formattedDisplayName(),
                email: ProfileDisplayNamePolicy.normalized(appleCredential?.email),
                credentialAlreadyDelivered: appleCredentialDeliveredForCurrentAuthorization
            )
            switch route {
            case .deliver(let payload):
#if DEBUG
                AppLog.authentication.debug("[AppleAuth] credentialReceived")
                AppLog.authentication.debug("[AppleAuth] identityTokenAvailable=true")
#endif
                ExperienceHaptics.play(.selection)
                appleCredentialDeliveredForCurrentAuthorization = true
                currentNonce = nil
                AppleAuthReleaseTrace.credentialHandoffToViewModel()
                onAppleCredential(payload)
            case .duplicateDelivery:
                AppleAuthReleaseTrace.authorizationCompleted(outcome: "duplicateIgnored")
#if DEBUG
                AppLog.authentication.debug("[AppleAuth] credential.request.duplicateIgnored")
#endif
            case .missingIdentityToken:
#if DEBUG
                AppLog.authentication.debug(
                    "[AppleAuth] credential.request.failed reason=missingIdentityToken identityToken.present=false authorizationCode.present=\(appleCredential?.authorizationCode != nil, privacy: .public)"
                )
#endif
                currentNonce = nil
                onAppleFailure(AuthenticationError.providerTokenInvalid(.apple))
            case .missingNonce:
                currentNonce = nil
                onAppleFailure(AuthenticationError.providerTokenInvalid(.apple))
            }

        case .failure(let error):
            currentNonce = nil
            appleCredentialDeliveredForCurrentAuthorization = false
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                AppleAuthReleaseTrace.authorizationCompleted(outcome: "cancelled")
#if DEBUG
                AppLog.authentication.debug("[AppleAuth] credential.request.cancelled")
#endif
                onAppleCancelled()
                return
            }
            AppleAuthReleaseTrace.authorizationCompleted(outcome: "failure")
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
