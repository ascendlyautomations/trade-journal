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

    var mode: Mode = .signIn
    var email: String = ""
    var password: String = ""
    var isSecurePasswordVisible: Bool = false
    var isSubmitting: Bool = false
    var errorMessage: String?
    var informationalMessage: String?

    private let authenticationCoordinator: AuthenticationCoordinator
    private let allowsDevelopmentBypass: Bool

    init(
        authenticationCoordinator: AuthenticationCoordinator,
        allowsDevelopmentBypass: Bool
    ) {
        self.authenticationCoordinator = authenticationCoordinator
        self.allowsDevelopmentBypass = allowsDevelopmentBypass
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

    func toggleMode() {
        ExperienceHaptics.play(.selection)
        mode = mode == .signIn ? .signUp : .signIn
        errorMessage = nil
        informationalMessage = nil
    }

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        informationalMessage = nil
        defer { isSubmitting = false }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch mode {
            case .signIn:
                try await authenticationCoordinator.signIn(email: trimmedEmail, password: password)
            case .signUp:
                try await authenticationCoordinator.signUp(email: trimmedEmail, password: password)
            }
            ExperienceHaptics.play(.success)
        } catch {
            present(error)
        }
    }

    func signInWithApple() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await authenticationCoordinator.signInWithApple()
            ExperienceHaptics.play(.success)
        } catch {
            present(error)
        }
    }

    func signInWithGoogle() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await authenticationCoordinator.signInWithGoogle()
            ExperienceHaptics.play(.success)
        } catch {
            present(error)
        }
    }

    func continueAsDevelopment() async {
        guard allowsDevelopmentBypass, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await authenticationCoordinator.continueAsDevelopmentSessionIfAllowed()
            ExperienceHaptics.play(.success)
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        ExperienceHaptics.play(.warning)
        if let auth = error as? AuthenticationError {
            if case .cancelled = auth {
                errorMessage = nil
                return
            }
            errorMessage = UserFacingError.map(auth).message
            return
        }
        if let app = error as? AppError {
            errorMessage = UserFacingError.map(app).message
            return
        }
        let appError = AppError.unknown(message: error.localizedDescription)
        errorMessage = UserFacingError.map(appError).message
    }
}
