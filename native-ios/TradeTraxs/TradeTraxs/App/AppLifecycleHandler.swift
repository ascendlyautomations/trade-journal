import Foundation
import OSLog
import SwiftUI

/// Clean lifecycle entry points. No business logic — log + push refresh hooks.
final class AppLifecycleHandler {
    /// Bound by ``TradeTraxsApp`` after composition.
    var pushNotifications: PushNotificationCenter?

    func handle(scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            applicationDidBecomeActive()
        case .inactive:
            applicationWillResignActive()
        case .background:
            applicationDidEnterBackground()
        @unknown default:
            AppLog.application.debug("Lifecycle: unknown scene phase")
        }
    }

    func applicationDidBecomeActive() {
        AppLog.application.info("Lifecycle: foreground / active")
        Task { @MainActor in
            await pushNotifications?.refreshAuthorizationStatus()
            pushNotifications?.syncBadgeFromActivity()
            await DailyCheckInReminderCoordinator.shared.sync()
        }
    }

    func applicationWillResignActive() {
        AppLog.application.info("Lifecycle: inactive")
        // Future: pause non-critical work.
    }

    func applicationDidEnterBackground() {
        AppLog.application.info("Lifecycle: background")
        // Future: flush analytics breadcrumbs, suspend channels.
    }

    func applicationWillTerminate() {
        AppLog.application.info("Lifecycle: termination")
        // Future: best-effort cleanup only — do not rely on this for durability.
    }
}
