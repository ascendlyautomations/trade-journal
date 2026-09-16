import Foundation
import Observation

@Observable
@MainActor
final class SettingsAccountViewModel {
    private let profiles: any ProfileRepository
    private let billing: any BillingRepository
    private let account: any AccountRepository
    private let session: any SessionProviding
    private let authenticationCoordinator: AuthenticationCoordinator
    private let navigationCoordinator: NavigationCoordinator

    private(set) var email: String?
    private(set) var username: String?
    private(set) var createdAt: Date?
    private(set) var billingStatus: BillingStatus?
    private(set) var isLoading = false
    private(set) var isDeletingAccount = false
    private(set) var errorMessage: String?
    private(set) var deleteErrorMessage: String?
    private(set) var passwordResetMessage: String?
    var confirmsLogout = false
    var showsDeleteAccountExplainer = false
    var showsDeleteAccountConfirmation = false
    private var hasLoaded = false

    init(
        profiles: any ProfileRepository,
        billing: any BillingRepository,
        account: any AccountRepository,
        session: any SessionProviding,
        authenticationCoordinator: AuthenticationCoordinator,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.profiles = profiles
        self.billing = billing
        self.account = account
        self.session = session
        self.authenticationCoordinator = authenticationCoordinator
        self.navigationCoordinator = navigationCoordinator
    }

    var usesAppleSignIn: Bool {
        authenticationCoordinator.currentSignInProvider == .apple
    }

    var deleteAccountExplainerMessage: String {
        var parts = [
            "Deleting your TradeTraxs account permanently deletes your account and associated data. This cannot be undone.",
        ]
        if let subscriptionNotice = subscriptionNoticeForDeletion {
            parts.append(subscriptionNotice)
        }
        if usesAppleSignIn {
            parts.append(
                "For Sign in with Apple, TradeTraxs removes your account data and revokes Sign in with Apple when Apple confirms it. If automatic revocation is not available for your account, you can also remove TradeTraxs under Settings → Apple ID → Sign in with Apple on your device after deletion."
            )
        }
        return parts.joined(separator: "\n\n")
    }

    var deleteAccountConfirmationMessage: String {
        "This permanently deletes your TradeTraxs account and associated data. This action cannot be undone."
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
                billingStatus = nil
                isLoading = false
                return
            }
            let profileID = ProfileID(userID.rawValue)
            async let profileTask = profiles.profile(id: profileID)
            async let billingTask = billing.status(for: profileID)
            let profile = try await profileTask
            username = profile.username
            createdAt = profile.createdAt
            billingStatus = try? await billingTask
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

    func requestDeleteAccount() {
        deleteErrorMessage = nil
        showsDeleteAccountExplainer = true
    }

    func proceedToDeleteConfirmation() {
        showsDeleteAccountExplainer = false
        showsDeleteAccountConfirmation = true
    }

    func cancelDeleteAccountFlow() {
        showsDeleteAccountExplainer = false
        showsDeleteAccountConfirmation = false
        clearDeleteError()
    }

    func clearDeleteError() {
        deleteErrorMessage = nil
    }

    func confirmDeleteAccount() {
        guard !isDeletingAccount else { return }
        showsDeleteAccountConfirmation = false
        isDeletingAccount = true
        deleteErrorMessage = nil
        Task {
            defer { isDeletingAccount = false }
            do {
                try await authenticationCoordinator.deleteAccount(using: account)
                ExperienceHaptics.play(.success)
            } catch AccountDeletionError.notAuthenticated {
                deleteErrorMessage = "Your session expired. Sign in again and retry."
                ExperienceHaptics.play(.error)
            } catch AccountDeletionError.serverMessage(let message) {
                deleteErrorMessage = message
                ExperienceHaptics.play(.error)
            } catch {
                deleteErrorMessage = UserFacingError.message(for: error)
                ExperienceHaptics.play(.error)
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

    private var subscriptionNoticeForDeletion: String? {
        guard let billingStatus else { return nil }
        guard billingStatus.hasTraxProAccess else { return nil }

        if billingStatus.entitlementSource == .apple {
            return """
            You have an active TraxPro subscription through the Apple App Store. Deleting your TradeTraxs account \
            removes your profile and data here, but does not cancel your Apple subscription. Manage or cancel it in \
            Settings → Apple ID → Subscriptions, or use Manage Subscription in TradeTraxs Settings.
            """
        }

        switch billingStatus.lifecycle {
        case .active, .trialing, .pastDue:
            break
        case .canceled, .expired, .none:
            return nil
        }

        let planLabel: String = {
            switch billingStatus.lifecycle {
            case .trialing: return "TraxPro trial"
            case .active where billingStatus.plan == .pro: return "TraxPro subscription"
            case .pastDue: return "TraxPro subscription (past due)"
            default:
                return billingStatus.plan == .pro ? "TraxPro membership" : "membership"
            }
        }()

        return """
        You currently have an active \(planLabel). Deleting your TradeTraxs account removes your profile and data. \
        Web (Stripe) billing tied to this account is cancelled when deletion succeeds. Deleting here does not \
        automatically cancel an Apple App Store subscription—manage Apple billing separately in Settings → Apple ID \
        → Subscriptions.
        """
    }
}
