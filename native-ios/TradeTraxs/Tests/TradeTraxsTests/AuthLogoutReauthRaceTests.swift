import Foundation
import Testing
@testable import TradeTraxs

@Suite(.serialized)
struct AuthLogoutReauthRaceTests {
    @Test("Auth token POST allowed while authenticated networking is blocked")
    func tokenExchangeSurvivesSessionEnd() async throws {
        let coordinator = NetworkConcurrencyCoordinator.shared
        await coordinator.markAuthenticatedSessionActive(authGeneration: 100)
        _ = await coordinator.resetForAuthenticatedSessionEnd(authGeneration: 101)

        let result = try await coordinator.runWithSlot(
            priority: .visible,
            path: "/auth/v1/token",
            host: "supabase",
            method: .post
        ) {
            "token-body"
        }
        #expect(result == "token-body")

        await coordinator.markAuthenticatedSessionActive(authGeneration: 102)
    }

    @Test("Session bootstrap RPC blocked while authenticated networking is blocked")
    func staleAuthenticatedRPCRejected() async throws {
        let coordinator = NetworkConcurrencyCoordinator.shared
        await coordinator.markAuthenticatedSessionActive(authGeneration: 200)
        _ = await coordinator.resetForAuthenticatedSessionEnd(authGeneration: 201)

        var cancelled = false
        do {
            _ = try await coordinator.runWithSlot(
                priority: .visible,
                path: "/rest/v1/rpc/rpc_v1_session_bootstrap",
                host: "supabase",
                method: .post
            ) {
                "must-not-run"
            }
        } catch {
            cancelled = true
        }
        #expect(cancelled)

        await coordinator.markAuthenticatedSessionActive(authGeneration: 202)
    }

    @Test("Remote logout POST may finish after session end")
    func remoteLogoutAllowedDuringSessionEnd() async throws {
        let coordinator = NetworkConcurrencyCoordinator.shared
        await coordinator.markAuthenticatedSessionActive(authGeneration: 300)
        _ = await coordinator.resetForAuthenticatedSessionEnd(authGeneration: 301)

        let result = try await coordinator.runWithSlot(
            priority: .visible,
            path: "/auth/v1/logout",
            host: "supabase",
            method: .post
        ) {
            "revoked"
        }
        #expect(result == "revoked")

        await coordinator.markAuthenticatedSessionActive(authGeneration: 302)
    }

    @Test("Auth network policy classifies GoTrue bootstrap paths")
    func authNetworkPolicy() {
        #expect(
            AuthNetworkPolicy.allowsDuringAuthenticatedSessionEnd(
                path: "/auth/v1/token",
                method: .post
            )
        )
        #expect(
            AuthNetworkPolicy.allowsDuringAuthenticatedSessionEnd(
                path: "/auth/v1/logout",
                method: .post
            )
        )
        #expect(
            !AuthNetworkPolicy.allowsDuringAuthenticatedSessionEnd(
                path: "/rest/v1/rpc/rpc_v1_session_bootstrap",
                method: .post
            )
        )
        #expect(
            !AuthNetworkPolicy.allowsDuringAuthenticatedSessionEnd(
                path: "/auth/v1/token",
                method: .get
            )
        )
    }

    @Test("Logout then login restores authenticated state")
    func logoutThenLoginStateMachine() async throws {
        AuthLifecycleGeneration.resetForTesting()
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        await NetworkConcurrencyCoordinator.shared.markAuthenticatedSessionActive(authGeneration: 0)

        try await auth.coordinator.signIn(email: "race@example.com", password: "password12")
        #expect(auth.manager.state.isAuthenticated)

        await auth.coordinator.logout()
        #expect(!auth.manager.state.isAuthenticated)

        try await auth.coordinator.signIn(email: "race@example.com", password: "password12")
        #expect(auth.manager.state.isAuthenticated)
        #expect(navigation.store.sessionPhase == .authenticated)

        await NetworkConcurrencyCoordinator.shared.markAuthenticatedSessionActive(authGeneration: 999)
    }
}
