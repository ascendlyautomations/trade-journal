import SwiftUI
import UIKit
import XCTest
@testable import TradeTraxs

@MainActor
final class AuthenticationExperienceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AuthLandingInstallState.shared.recordLoggedOutAuthLandingPresented()
    }

    func testFreshInstallDefaultsToCreateAccountMode() {
        let suiteName = "AuthLandingInstallStateTests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let installState = AuthLandingInstallState(defaults: defaults)
        XCTAssertEqual(installState.initialLoginMode, .signUp)
        installState.recordLoggedOutAuthLandingPresented()
        XCTAssertEqual(installState.initialLoginMode, .signIn)
    }

    func testLoginViewModelRejectsEmptySubmit() async {
        let auth = CompositionRoot.bootstrapAuthenticationForTests()
        let viewModel = LoginViewModel(
            authenticationCoordinator: auth.coordinator,
            allowsDevelopmentBypass: true
        )
        XCTAssertFalse(viewModel.canSubmit)
        await viewModel.submit()
        XCTAssertEqual(viewModel.errorMessage, "Enter your email address.")
        XCTAssertFalse(auth.manager.state.isAuthenticated)
    }

    func testLoginViewModelSignUpEmailConfirmationPending() async {
        let navigation = CompositionRoot.bootstrapNavigation()
        let backend = InMemoryAuthenticationBackend()
        backend.signUpRequiresEmailConfirmation = true
        let auth = CompositionRoot.bootstrapAuthenticationForTests(
            navigation: navigation,
            backend: backend
        )
        _ = auth.manager.prepareColdLaunch()
        let viewModel = LoginViewModel(
            authenticationCoordinator: auth.coordinator,
            allowsDevelopmentBypass: false
        )
        viewModel.mode = .signUp
        viewModel.fullName = "Pending User"
        viewModel.email = "pending@tradetraxs.com"
        viewModel.password = "password1"
        await viewModel.submit()
        XCTAssertFalse(auth.manager.state.isAuthenticated)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.pendingConfirmationEmail, "pending@tradetraxs.com")
        XCTAssertEqual(viewModel.mode, .signIn)
        XCTAssertNotNil(viewModel.informationalMessage)
    }

    func testCreateAccountDuplicateEmailRendersOnSignIn() async {
        let backend = InMemoryAuthenticationBackend()
        backend.signInError = .emailAlreadyRegistered
        let auth = CompositionRoot.bootstrapAuthenticationForTests(backend: backend)
        _ = auth.manager.prepareColdLaunch()
        let viewModel = LoginViewModel(
            authenticationCoordinator: auth.coordinator,
            allowsDevelopmentBypass: false
        )
        viewModel.mode = .signUp
        viewModel.fullName = "Nick"
        viewModel.email = "example@email.com"
        viewModel.password = "password1"
        await viewModel.submit()
        viewModel.noteCredentialsEdited()
        viewModel.notePasswordEdited()

        XCTAssertFalse(auth.manager.state.isAuthenticated)
        XCTAssertEqual(viewModel.mode, .signIn)
        XCTAssertEqual(viewModel.email, "example@email.com")
        XCTAssertEqual(viewModel.password, "")
        XCTAssertFalse(viewModel.isSubmitting)
        XCTAssertNotNil(viewModel.duplicateEmailNotice)
        XCTAssertEqual(viewModel.duplicateEmailNotice, LoginViewModel.duplicateEmailSignInMessage)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotEqual(viewModel.duplicateEmailNotice, SignInFormErrorPresentation.genericFailure)

        let navigation = CompositionRoot.bootstrapNavigation()
        let rendered = renderedSignInText(
            LoginView(viewModel: viewModel, navigationCoordinator: navigation.coordinator)
        )
        XCTAssertEqual(viewModel.mode, .signIn)
        XCTAssertTrue(
            rendered.contains(LoginViewModel.duplicateEmailSignInMessage),
            "Sign In did not render the duplicate-email notice. Rendered: \(rendered)"
        )

        viewModel.toggleMode()
        XCTAssertEqual(viewModel.mode, .signUp)
        XCTAssertNil(viewModel.duplicateEmailNotice)

        viewModel.mode = .signUp
        viewModel.fullName = "Nick"
        viewModel.email = "example@email.com"
        viewModel.password = "password1"
        await viewModel.submit()
        XCTAssertEqual(viewModel.mode, .signIn)
        XCTAssertEqual(viewModel.duplicateEmailNotice, LoginViewModel.duplicateEmailSignInMessage)

        backend.signInError = nil
        viewModel.password = "password1"
        await viewModel.submit()
        XCTAssertTrue(auth.manager.state.isAuthenticated)
        XCTAssertNil(viewModel.duplicateEmailNotice)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateAccountOtherFailureUsesGenericCopy() async {
        let backend = InMemoryAuthenticationBackend()
        backend.signInError = .unknown(SignInFormErrorPresentation.Reason.serverUnavailable)
        let auth = CompositionRoot.bootstrapAuthenticationForTests(backend: backend)
        _ = auth.manager.prepareColdLaunch()
        let viewModel = LoginViewModel(
            authenticationCoordinator: auth.coordinator,
            allowsDevelopmentBypass: false
        )
        viewModel.mode = .signUp
        viewModel.fullName = "Alex Trader"
        viewModel.email = "new@tradetraxs.com"
        viewModel.password = "password1"
        await viewModel.submit()

        XCTAssertEqual(viewModel.mode, .signUp)
        XCTAssertEqual(viewModel.fullName, "Alex Trader")
        XCTAssertEqual(viewModel.email, "new@tradetraxs.com")
        XCTAssertFalse(viewModel.isSubmitting)
        XCTAssertEqual(viewModel.errorMessage, SignInFormErrorPresentation.genericFailure)
    }

    func testLoginViewModelSignUpImmediateSession() async {
        let auth = CompositionRoot.bootstrapAuthenticationForTests()
        _ = auth.manager.prepareColdLaunch()
        let viewModel = LoginViewModel(
            authenticationCoordinator: auth.coordinator,
            allowsDevelopmentBypass: false
        )
        viewModel.mode = .signUp
        viewModel.fullName = "New User"
        viewModel.email = "new@tradetraxs.com"
        viewModel.password = "password1"
        await viewModel.submit()
        XCTAssertTrue(auth.manager.state.isAuthenticated)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.pendingConfirmationEmail)
    }

    func testLoginViewModelWrongPasswordShowsIncorrectCredentials() async {
        let backend = InMemoryAuthenticationBackend()
        backend.signInError = .invalidCredentials
        let auth = CompositionRoot.bootstrapAuthenticationForTests(backend: backend)
        _ = auth.manager.prepareColdLaunch()
        let viewModel = LoginViewModel(
            authenticationCoordinator: auth.coordinator,
            allowsDevelopmentBypass: false
        )
        viewModel.email = "trader@tradetraxs.com"
        viewModel.password = "wrong-password"
        await viewModel.submit()
        XCTAssertFalse(auth.manager.state.isAuthenticated)
        XCTAssertEqual(viewModel.errorMessage, SignInFormErrorPresentation.incorrectCredentials)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    func testLoginViewModelNetworkFailureShowsConnectionCopy() async {
        let backend = InMemoryAuthenticationBackend()
        backend.signInError = .unknown(SignInFormErrorPresentation.Reason.networkUnavailable)
        let auth = CompositionRoot.bootstrapAuthenticationForTests(backend: backend)
        _ = auth.manager.prepareColdLaunch()
        let viewModel = LoginViewModel(
            authenticationCoordinator: auth.coordinator,
            allowsDevelopmentBypass: false
        )
        viewModel.email = "trader@tradetraxs.com"
        viewModel.password = "password1"
        await viewModel.submit()
        XCTAssertEqual(viewModel.errorMessage, SignInFormErrorPresentation.networkUnavailable)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    func testLoginViewModelSignInSuccess() async throws {
        let auth = CompositionRoot.bootstrapAuthenticationForTests()
        _ = auth.manager.prepareColdLaunch()
        let viewModel = LoginViewModel(
            authenticationCoordinator: auth.coordinator,
            allowsDevelopmentBypass: false
        )
        viewModel.email = "trader@tradetraxs.com"
        viewModel.password = "password1"
        await viewModel.submit()
        XCTAssertTrue(auth.manager.state.isAuthenticated)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoginViewModelModeToggle() {
        let auth = CompositionRoot.bootstrapAuthenticationForTests()
        let viewModel = LoginViewModel(
            authenticationCoordinator: auth.coordinator,
            allowsDevelopmentBypass: false
        )
        XCTAssertEqual(viewModel.mode, .signIn)
        viewModel.toggleMode()
        XCTAssertEqual(viewModel.mode, .signUp)
        XCTAssertEqual(viewModel.primaryButtonTitle, "Create Account")
    }

    func testResetPasswordViewModelSuccess() async {
        let auth = CompositionRoot.bootstrapAuthenticationForTests()
        let viewModel = ResetPasswordViewModel(authenticationCoordinator: auth.coordinator)
        viewModel.email = "trader@tradetraxs.com"
        await viewModel.submit()
        XCTAssertTrue(viewModel.didSucceed)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testDevelopmentContinueRequiresBypassFlag() async {
        let auth = CompositionRoot.bootstrapAuthenticationForTests()
        _ = auth.manager.prepareColdLaunch()
        let viewModel = LoginViewModel(
            authenticationCoordinator: auth.coordinator,
            allowsDevelopmentBypass: false
        )
        await viewModel.continueAsDevelopment()
        XCTAssertFalse(auth.manager.state.isAuthenticated)
    }

    func testSecureLogoutReturnsUnauthenticated() async throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        try await auth.coordinator.signIn(email: "a@b.com", password: "password1")
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)
        await auth.coordinator.logout()
        XCTAssertEqual(navigation.store.sessionPhase, .unauthenticated)
        XCTAssertFalse(auth.manager.state.isAuthenticated)
    }

    private func renderedSignInText<V: View>(_ view: V) -> String {
        let size = CGSize(width: 390, height: 844)
        let host = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let texts = Self.collectedText(in: host.view)
        window.isHidden = true
        return texts.joined(separator: "\n")
    }

    private static func collectedText(in view: UIView) -> [String] {
        var texts: [String] = []
        var visited = Set<ObjectIdentifier>()
        collect(view, into: &texts, visited: &visited)
        return texts
    }

    private static func collect(_ object: NSObject, into texts: inout [String], visited: inout Set<ObjectIdentifier>) {
        let identity = ObjectIdentifier(object)
        guard visited.insert(identity).inserted else { return }
        if let label = object.accessibilityLabel, !label.isEmpty {
            texts.append(label)
        }
        if let identified = object as? UIAccessibilityIdentification,
           let identifier = identified.accessibilityIdentifier,
           !identifier.isEmpty {
            texts.append(identifier)
        }
        if let label = object as? UILabel, let text = label.text, !text.isEmpty {
            texts.append(text)
        }
        if let view = object as? UIView {
            for child in view.subviews {
                collect(child, into: &texts, visited: &visited)
            }
        }
        let count = object.accessibilityElementCount()
        guard count > 0, count < 400 else { return }
        for index in 0..<count {
            guard let child = object.accessibilityElement(at: index) as? NSObject else { continue }
            collect(child, into: &texts, visited: &visited)
        }
    }

    func testThemePersistenceSurvivesLogout() async throws {
        let environment = CompositionRoot.bootstrapAppEnvironment()
        let before = environment.themeManager.selectedIdentifier
        try await environment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
        await environment.authentication.coordinator.logout()
        XCTAssertEqual(environment.themeManager.selectedIdentifier, before)
    }
}
