import Foundation
import Observation

@Observable
@MainActor
final class SettingsAccountViewModel {
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let authenticationCoordinator: AuthenticationCoordinator
    private let navigationCoordinator: NavigationCoordinator

    private(set) var email: String?
    private(set) var username: String?
    private(set) var createdAt: Date?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var passwordResetMessage: String?
    var confirmsLogout = false
    private var hasLoaded = false

    init(
        profiles: any ProfileRepository,
        session: any SessionProviding,
        authenticationCoordinator: AuthenticationCoordinator,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.profiles = profiles
        self.session = session
        self.authenticationCoordinator = authenticationCoordinator
        self.navigationCoordinator = navigationCoordinator
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = email == nil && username == nil
        email = authenticationCoordinator.sessionEmail
        do {
            guard let userID = await session.currentUserID else {
                errorMessage = "Sign in to view your account."
                isLoading = false
                return
            }
            let profile = try await profiles.profile(id: ProfileID(userID.rawValue))
            username = profile.username
            createdAt = profile.createdAt
            if email == nil {
                email = try? await profiles.currentUser().email
            }
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
        isLoading = false
    }

    func requestPasswordReset() {
        guard let email, !email.isEmpty else {
            passwordResetMessage = "No email is available for this account."
            return
        }
        Task {
            do {
                try await authenticationCoordinator.requestPasswordReset(email: email)
                passwordResetMessage = "Password reset email sent to \(email)."
                ExperienceHaptics.play(.success)
            } catch {
                passwordResetMessage = UserFacingError.message(for: error)
                ExperienceHaptics.play(.warning)
            }
        }
    }

    func logout() {
        confirmsLogout = false
        ExperienceHaptics.play(.selection)
        Task {
            await authenticationCoordinator.logout()
        }
    }
}
