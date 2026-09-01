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
    private var activeSignInTask: Task<Void, Never>?

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
        await runSignIn(label: "login.tap") { [self] in
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            switch mode {
            case .signIn:
                try await authenticationCoordinator.signIn(email: trimmedEmail, password: password)
            case .signUp:
                try await authenticationCoordinator.signUp(email: trimmedEmail, password: password)
            }
        }
    }

    func signInWithApple(credential: AppleIDCredentialPayload) async {
        await runSignIn(label: "login.tap.apple") { [self] in
            try await authenticationCoordinator.signInWithApple(credential: credential)
        }
    }

    func handleAppleSignInCancelled() {
        errorMessage = nil
        isSubmitting = false
    }

    func handleAppleSignInFailure(_ error: Error) {
        isSubmitting = false
        present(error)
    }

    func signInWithGoogle() async {
        await runSignIn(label: "login.tap.google") { [self] in
            try await authenticationCoordinator.signInWithGoogle()
        }
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

        let task = Task {
            defer {
                if !Task.isCancelled {
                    isSubmitting = false
                }
            }
            AuthFlowTracer.trace(label, phase: .authenticating)
            do {
                try await operation()
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
