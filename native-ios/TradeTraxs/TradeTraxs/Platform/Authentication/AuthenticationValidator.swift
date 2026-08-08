import Foundation

/// Input validation for auth forms — no networking.
nonisolated struct AuthenticationValidator: Sendable {
    func validateEmail(_ email: String) -> AuthenticationError? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalidEmail }
        guard trimmed.contains("@"), trimmed.contains(".") else { return .invalidEmail }
        return nil
    }

    func validatePassword(_ password: String) -> AuthenticationError? {
        guard password.count >= 8 else {
            return .invalidPassword
        }
        return nil
    }

    func validateSignIn(email: String, password: String) -> AuthenticationError? {
        if let emailError = validateEmail(email) { return emailError }
        if password.isEmpty { return .invalidPassword }
        return nil
    }
}
