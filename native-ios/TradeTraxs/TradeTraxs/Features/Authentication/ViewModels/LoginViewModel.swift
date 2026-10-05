import Foundation
import Observation

/// Owns login / sign-up form state. Talks only to ``AuthenticationCoordinator``.
@Observable
@MainActor
final class LoginViewModel {
    enum Mode: String, CaseIterable, Sendable {
        case signIn
        case signUp
    }

    var mode: Mode
    var fullName: String = ""
    var email: String = ""
    var password: String = ""
    var isSecurePasswordVisible: Bool = false
    var isSubmitting: Bool = false
    /// True from Apple/Google interaction start through token exchange (covers system UI latency).
    private(set) var isOAuthInteractionInFlight: Bool = false
    var errorMessage: String?
    /// Survives the Create Account → Sign In handoff. Credential edits must not clear it.
    var duplicateEmailNotice: String?
    var informationalMessage: String?
    var pendingConfirmationEmail: String?
    var isResendingConfirmation = false
    var confirmationResentMessage: String?

    private let authenticationCoordinator: AuthenticationCoordinator
    private let allowsDevelopmentBypass: Bool
    private let validator = AuthenticationValidator()
    private var activeSignInTask: Task<Void, Never>?

    init(
        authenticationCoordinator: AuthenticationCoordinator,
        allowsDevelopmentBypass: Bool,
        initialMode: Mode? = nil
    ) {
        self.authenticationCoordinator = authenticationCoordinator
        self.allowsDevelopmentBypass = allowsDevelopmentBypass
        self.mode = initialMode ?? AuthLandingInstallState.shared.initialLoginMode
    }

    var primaryButtonTitle: String {
        mode == .signIn ? "Sign In" : "Create Account"
    }

    var canSubmit: Bool {
        !isSubmitting
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 6
    }

    var showsDevelopmentContinue: Bool { allowsDevelopmentBypass }

    static let duplicateEmailSignInMessage =
        "That email is already in use. Sign in to the existing account below, or tap Create Account to use a different email."

    func toggleMode() {
        ExperienceHaptics.play(.selection)
        mode = mode == .signIn ? .signUp : .signIn
        errorMessage = nil
        duplicateEmailNotice = nil
        informationalMessage = nil
        pendingConfirmationEmail = nil
        confirmationResentMessage = nil
    }

    func noteCredentialsEdited() {
        errorMessage = nil
    }

    /// Password edits clear ordinary form errors. The duplicate-email notice is separate and stays.
    func notePasswordEdited() {
        guard errorMessage != Self.duplicateEmailSignInMessage else { return }
        errorMessage = nil
    }

    func submit() async {
        guard !isOAuthInteractionInFlight else { return }
        if let message = validationMessage() {
            ExperienceHaptics.play(.warning)
            errorMessage = message
            return
        }
        guard canSubmit else { return }
        await runSignIn(label: "login.tap") { [self] in
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            switch mode {
            case .signIn:
                try await authenticationCoordinator.signIn(
                    email: trimmedEmail,
                    password: password,
                    smartSignUpIfNewEmail: true
                )
            case .signUp:
                let normalizedName = ProfileDisplayNamePolicy.normalized(fullName)
                try await authenticationCoordinator.signUp(
                    email: trimmedEmail,
                    password: password,
                    fullName: normalizedName
                )
            }
        }
    }

    func beginOAuthProviderInteraction() {
        isOAuthInteractionInFlight = true
    }

    func endOAuthProviderInteraction() {
        isOAuthInteractionInFlight = false
    }

    /// Apple / Google — same pipeline regardless of email Sign In vs Create Account mode.
    func signInWithApple(credential: AppleIDCredentialPayload) async {
        if isSubmitting {
            endOAuthProviderInteraction()
            errorMessage = "Sign-in is already in progress. Please wait a moment."
            return
        }
        await runSignIn(label: "login.tap.apple") { [self] in
            try await authenticationCoordinator.signInWithApple(credential: credential)
        }
        endOAuthProviderInteraction()
    }

    func handleAppleSignInCancelled() {
        errorMessage = nil
        isSubmitting = false
        endOAuthProviderInteraction()
    }

    func handleAppleSignInFailure(_ error: Error) {
        isSubmitting = false
        endOAuthProviderInteraction()
        present(error)
    }

    func signInWithGoogle() async {
        guard !isSubmitting else { return }
        await runSignIn(label: "login.tap.google") { [self] in
            try await authenticationCoordinator.signInWithGoogle()
        }
        endOAuthProviderInteraction()
    }

    func continueAsDevelopment() async {
        guard allowsDevelopmentBypass else { return }
        await runSignIn(label: "login.tap.development") { [self] in
            try await authenticationCoordinator.continueAsDevelopmentSessionIfAllowed()
        }
    }

    private func runSignIn(
        label: String,
        operation: @escaping () async throws -> Void
    ) async {
        guard !isSubmitting else { return }
        activeSignInTask?.cancel()
        isSubmitting = true
        errorMessage = nil
        informationalMessage = nil
        pendingConfirmationEmail = nil
        confirmationResentMessage = nil

        let task = Task {
            defer {
                if !Task.isCancelled {
                    isSubmitting = false
                }
            }
            AuthFlowTracer.trace(label, phase: .authenticating)
            do {
                try await operation()
                errorMessage = nil
                duplicateEmailNotice = nil
                ExperienceHaptics.play(.success)
            } catch is CancellationError {
                isSubmitting = false
            } catch {
                isSubmitting = false
                present(error)
            }
        }
        activeSignInTask = task
        await task.value
    }

    func resendConfirmationEmail() async {
        guard let pendingConfirmationEmail,
              !pendingConfirmationEmail.isEmpty,
              !isResendingConfirmation
        else { return }
        isResendingConfirmation = true
        confirmationResentMessage = nil
        defer { isResendingConfirmation = false }
        do {
            try await authenticationCoordinator.resendSignupConfirmation(
                email: pendingConfirmationEmail
            )
            confirmationResentMessage = "Confirmation email sent. Check your inbox."
            ExperienceHaptics.play(.success)
        } catch {
            confirmationResentMessage = UserFacingError.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }

    private func validationMessage() -> String? {
        if mode == .signUp, let nameMessage = ProfileDisplayNamePolicy.validateRequired(fullName) {
            return nameMessage
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty {
            return "Enter your email address."
        }
        if validator.validateEmail(email) != nil {
            return "Enter a valid email address."
        }
        if password.isEmpty {
            return "Enter your password."
        }
        if mode == .signUp, validator.validatePassword(password) != nil {
            return "Password must be at least 8 characters."
        }
        return nil
    }

    private func present(_ error: Error) {
        ExperienceHaptics.play(.warning)
        if let auth = error as? AuthenticationError {
            if case .cancelled = auth {
                errorMessage = nil
                return
            }
            if case .emailConfirmationRequired(let email) = auth {
                errorMessage = nil
                pendingConfirmationEmail = email
                OAuthProfileOnboardingNameStore.stageManualSignupPendingEmail(
                    fullName: fullName,
                    email: email
                )
                informationalMessage =
                    "We sent a confirmation link to \(email). Confirm your email, then sign in."
                mode = .signIn
                return
            }
            if case .emailAlreadyRegistered = auth {
                if mode == .signUp {
                    mode = .signIn
                    password = ""
                    isSubmitting = false
                    errorMessage = nil
                    duplicateEmailNotice = Self.duplicateEmailSignInMessage
                    return
                }
                errorMessage = nil
                duplicateEmailNotice = Self.duplicateEmailSignInMessage
                return
            }
            let message = SignInFormErrorPresentation.inlineMessage(for: auth)
            errorMessage = message.isEmpty ? nil : message
            return
        }
        if let app = error as? AppError {
            let message = SignInFormErrorPresentation.inlineMessage(for: app)
            errorMessage = message.isEmpty ? nil : message
            return
        }
        let message = SignInFormErrorPresentation.inlineMessage(for: error)
        errorMessage = message.isEmpty ? nil : message
    }
}
