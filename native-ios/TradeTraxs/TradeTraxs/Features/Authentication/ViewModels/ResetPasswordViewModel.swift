import Foundation
import Observation

@Observable
@MainActor
final class ResetPasswordViewModel {
    var email: String = ""
    var isSubmitting: Bool = false
    var errorMessage: String?
    var didSucceed: Bool = false

    private let authenticationCoordinator: AuthenticationCoordinator

    init(authenticationCoordinator: AuthenticationCoordinator) {
        self.authenticationCoordinator = authenticationCoordinator
    }

    var canSubmit: Bool {
        !isSubmitting && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await authenticationCoordinator.requestPasswordReset(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            didSucceed = true
            ExperienceHaptics.play(.success)
        } catch let auth as AuthenticationError {
            ExperienceHaptics.play(.warning)
            errorMessage = UserFacingError.map(auth).message
        } catch {
            ExperienceHaptics.play(.warning)
            let appError = AppError.unknown(message: error.localizedDescription)
            errorMessage = UserFacingError.map(appError).message
        }
    }
}
