import Foundation
import LocalAuthentication

/// Biometric unlock extension point — disabled until product enables it.
nonisolated protocol BiometricAuthenticating: Sendable {
    var isAvailable: Bool { get }
    func evaluate(reason: String) async throws
}

nonisolated struct BiometricAuthenticationSupport: BiometricAuthenticating {
    var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func evaluate(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw AuthenticationError.biometricUnavailable
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            guard success else { throw AuthenticationError.biometricFailed }
        } catch {
            throw AuthenticationError.biometricFailed
        }
    }
}

nonisolated struct DisabledBiometricAuthenticationSupport: BiometricAuthenticating {
    var isAvailable: Bool { false }
    func evaluate(reason: String) async throws {
        _ = reason
        throw AuthenticationError.biometricUnavailable
    }
}
