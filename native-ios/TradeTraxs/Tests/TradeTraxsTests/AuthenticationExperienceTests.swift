import XCTest
@testable import TradeTraxs

@MainActor
final class AuthenticationExperienceTests: XCTestCase {
    func testLoginViewModelRejectsEmptySubmit() async {
        let auth = CompositionRoot.bootstrapAuthenticationForTests()
        let viewModel = LoginViewModel(
            authenticationCoordinator: auth.coordinator,
            allowsDevelopmentBypass: true
        )
        XCTAssertFalse(viewModel.canSubmit)
        await viewModel.submit()
        XCTAssertFalse(auth.manager.state.isAuthenticated)
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
        XCTAssertFalse(viewModel.showsDevelopmentContinue)
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

    func testThemePersistenceSurvivesLogout() async throws {
        let environment = CompositionRoot.bootstrap()
        let before = environment.themeManager.selectedIdentifier
        try await environment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
        await environment.authentication.coordinator.logout()
        XCTAssertEqual(environment.themeManager.selectedIdentifier, before)
    }
}
