import Foundation
import OSLog

/// Routes Apple authorization UI completions without depending on button enabled/loading state.
enum SocialSignInAppleCompletionRouting {
    enum SuccessRoute: Equatable {
        case deliver(AppleIDCredentialPayload)
        case missingIdentityToken
        case missingNonce
        case duplicateDelivery
    }

    static func routeSuccessfulAuthorization(
        idToken: String?,
        rawNonce: String?,
        authorizationCode: String?,
        fullName: String?,
        email: String?,
        credentialAlreadyDelivered: Bool
    ) -> SuccessRoute {
        if credentialAlreadyDelivered {
            return .duplicateDelivery
        }
        guard let idToken, !idToken.isEmpty else {
            return .missingIdentityToken
        }
        guard let rawNonce, !rawNonce.isEmpty else {
            return .missingNonce
        }
        return .deliver(
            AppleIDCredentialPayload(
                idToken: idToken,
                nonce: rawNonce,
                authorizationCode: authorizationCode?.isEmpty == false ? authorizationCode : nil,
                fullName: fullName,
                email: email
            )
        )
    }
}

enum AppleAuthReleaseTrace {
    static func authorizationCompleted(outcome: String) {
        AppLog.authentication.info("[AppleAuth] authorizationCompleted outcome=\(outcome, privacy: .public)")
    }

    static func credentialHandoffToViewModel() {
        AppLog.authentication.info("[AppleAuth] credentialHandoffToViewModel")
    }
}
