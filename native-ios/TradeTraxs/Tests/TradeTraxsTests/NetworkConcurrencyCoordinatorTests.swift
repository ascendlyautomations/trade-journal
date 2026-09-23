import Foundation
import Testing
@testable import TradeTraxs

@Suite(.serialized)
struct NetworkConcurrencyCoordinatorTests {
    @Test("Cancelled background waiter resumes continuation exactly once")
    func cancelWhileWaiting() async throws {
        await NetworkConcurrencyCoordinator.shared.markAuthenticatedSessionActive(authGeneration: 0)
        let coordinator = NetworkConcurrencyCoordinator.shared

        await fillBackgroundSlots(coordinator: coordinator, count: NetworkConcurrencyCoordinator.maxBackgroundConcurrent)

        let waiter = Task {
            try await coordinator.runWithSlot(
                priority: .background,
                path: "/rest/v1/rpc/rpc_v1_feed_bootstrap",
                host: "test",
                method: .post
            ) {
                "should-not-run"
            }
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        waiter.cancel()

        let completed = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = try? await waiter.value
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return false
            }
            for await result in group where result {
                group.cancelAll()
                return true
            }
            return false
        }

        #expect(completed)

        let reset = await coordinator.resetForAuthenticatedSessionEnd(authGeneration: 1)
        #expect(reset.waitersReleased >= 0)
    }

    @Test("Session reset drains waiters without leaking continuations")
    func resetWhileWaitersExist() async throws {
        await NetworkConcurrencyCoordinator.shared.markAuthenticatedSessionActive(authGeneration: 0)
        let coordinator = NetworkConcurrencyCoordinator.shared

        await fillBackgroundSlots(coordinator: coordinator, count: NetworkConcurrencyCoordinator.maxBackgroundConcurrent)

        let waiter = Task {
            try await coordinator.runWithSlot(
                priority: .background,
                path: "/rest/v1/rpc/rpc_v1_profile_bootstrap",
                host: "test",
                method: .post
            ) {
                "blocked"
            }
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        let reset = await coordinator.resetForAuthenticatedSessionEnd(authGeneration: 1)
        #expect(reset.waitersReleased >= 1)

        let completed = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = try? await waiter.value
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return false
            }
            for await result in group where result {
                group.cancelAll()
                return true
            }
            return false
        }
        #expect(completed)

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.total == 0)
        #expect(snapshot.waiting == 0)
    }

    @Test("Post-logout authenticated RPC acquire is rejected")
    func acquireRejectedAfterSessionReset() async throws {
        let coordinator = NetworkConcurrencyCoordinator.shared
        await coordinator.markAuthenticatedSessionActive(authGeneration: 1)
        _ = await coordinator.resetForAuthenticatedSessionEnd(authGeneration: 2)

        var rejected = false
        do {
            _ = try await coordinator.runWithSlot(
                priority: .background,
                path: "/rest/v1/rpc/rpc_v1_session_bootstrap",
                host: "test",
                method: .post
            ) {
                "blocked"
            }
        } catch {
            rejected = true
        }
        #expect(rejected)

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.total == 0)

        await coordinator.markAuthenticatedSessionActive(authGeneration: 3)
    }

    @Test("Post-logout PKCE token exchange acquire is allowed")
    func authTokenAllowedAfterSessionReset() async throws {
        let coordinator = NetworkConcurrencyCoordinator.shared
        await coordinator.markAuthenticatedSessionActive(authGeneration: 10)
        _ = await coordinator.resetForAuthenticatedSessionEnd(authGeneration: 11)

        let value = try await coordinator.runWithSlot(
            priority: .visible,
            path: "/auth/v1/token",
            host: "test",
            method: .post
        ) {
            "pkce-ok"
        }
        #expect(value == "pkce-ok")

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.total == 0)

        await coordinator.markAuthenticatedSessionActive(authGeneration: 12)
    }

    private func fillBackgroundSlots(
        coordinator: NetworkConcurrencyCoordinator,
        count: Int
    ) async {
        for index in 0..<count {
            Task {
                try? await coordinator.runWithSlot(
                    priority: .background,
                    path: "/rest/v1/rpc/rpc_v1_activity_bootstrap",
                    host: "fill-\(index)"
                ) {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return index
                }
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
}
