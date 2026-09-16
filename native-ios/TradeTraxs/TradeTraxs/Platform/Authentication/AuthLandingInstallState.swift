import Foundation

/// Distinguishes a genuine fresh install from returning logged-out users on the same device.
///
/// Fresh installs default ``LoginViewModel`` to Create Account once; every later logged-out
/// landing (including logout) defaults to Sign In.
struct AuthLandingInstallState {
    private static let hasPresentedLoggedOutLandingKey = "tt.auth.install.hasPresentedLoggedOutLanding"

    private let defaults: UserDefaults

    static let shared = AuthLandingInstallState()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var initialLoginMode: LoginViewModel.Mode {
        defaults.bool(forKey: Self.hasPresentedLoggedOutLandingKey) ? .signIn : .signUp
    }

    func recordLoggedOutAuthLandingPresented() {
        defaults.set(true, forKey: Self.hasPresentedLoggedOutLandingKey)
    }

#if DEBUG
    func resetForTesting() {
        defaults.removeObject(forKey: Self.hasPresentedLoggedOutLandingKey)
    }
#endif
}
