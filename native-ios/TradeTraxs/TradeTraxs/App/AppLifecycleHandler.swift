import Foundation
import OSLog
import SwiftUI

/// Clean lifecycle entry points. No business logic, log + push refresh hooks.
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
        ProductAnalyticsCoordinator.shared.handleBecameActive()
        #if DEBUG
        MediaEgressTracker.startPeriodicSummaries()
        #endif
        Task { @MainActor in
            let voice = RoomLiveVoiceCoordinator.shared
            if voice.session != nil {
                try? TradeRoomLiveVoiceAudioSession.shared.updateRequiresRecording(
                    voice.session?.canPublish == true
                )
                voice.refreshVoiceChromeAfterForeground()
                voice.refreshLiveActivityAfterForeground()
            }
            let broadcast = RoomBroadcastCoordinator.shared
            if broadcast.watchSession != nil {
                broadcast.refreshBroadcastSessionAfterForeground()
                broadcast.refreshBroadcastLiveActivityAfterForeground()
            }
            await pushNotifications?.refreshAuthorizationStatus()
            if AuthBootstrapReadiness.allowsAuthenticatedBackgroundWork() {
                pushNotifications?.syncBadgeFromActivity()
                pushNotifications?.refreshRemoteTokenIfAuthorized()
            }
            await DailyCheckInReminderCoordinator.shared.sync()
            await TradeImportReminderCoordinator.shared.sync()
        }
    }

    func applicationWillResignActive() {
        AppLog.application.info("Lifecycle: inactive")
        ProductAnalyticsCoordinator.shared.handleEnterBackground()
    }

    func applicationDidEnterBackground() {
        AppLog.application.info("Lifecycle: background")
        ProductAnalyticsCoordinator.shared.handleEnterBackground()
        #if DEBUG
        MediaEgressTracker.stopPeriodicSummaries()
        MediaEgressTracker.printSummary()
        #endif
    }

    func applicationWillTerminate() {
        AppLog.application.info("Lifecycle: termination")
        // Future: best-effort cleanup only, do not rely on this for durability.
    }
}
