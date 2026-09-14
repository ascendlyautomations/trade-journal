import Foundation
import Observation

/// Owns the process ``AppEnvironment`` and completes deferred bootstrap on demand (sign-in).
@Observable
@MainActor
final class AppLaunchController {
    static let shared = AppLaunchController()

    private(set) var environment: AppEnvironment
    private(set) var bootstrapGeneration: UInt64 = 0

    private var deferredContext: DeferredBootstrapContext?
    private var fullBootstrapTask: Task<AppEnvironment, Never>?

    private init() {
        StartupTrace.begin("AppLaunchController.init")
        StartupTrace.anchorAppStartIfNeeded()
        StartupTrace.event("swiftUIAppInit")
        let result = CompositionRoot.bootstrap()
        environment = result.environment
        deferredContext = result.deferredContext
        StartupTrace.end("AppLaunchController.init")
        // Logged-out: production stack loads only via ``ensureFullBootstrapComplete()`` (sign-in).
    }

    /// Sign-in and other authenticated operations await the live data/network stack.
    func ensureFullBootstrapComplete() async {
        guard deferredContext != nil || environment.isDeferredBootstrapPending else { return }
        if let task = fullBootstrapTask {
            _ = await task.value
            return
        }
        guard let deferredContext else { return }
        StartupTrace.event("ensureFullBootstrapComplete.started")
        let context = deferredContext
        fullBootstrapTask = Task { @MainActor in
            StartupTrace.begin("CompositionRoot.completeDeferredBootstrap")
            let full = await CompositionRoot.completeDeferredBootstrap(context: context)
            StartupTrace.end("CompositionRoot.completeDeferredBootstrap")
            self.applyFullEnvironment(full)
            return full
        }
        _ = await fullBootstrapTask?.value
    }

    private func applyFullEnvironment(_ full: AppEnvironment) {
        environment = full
        bootstrapGeneration &+= 1
        deferredContext = nil
        fullBootstrapTask = nil
    }
}
