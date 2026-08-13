import OSLog
import UIKit
import UserNotifications

/// UIKit application delegate for process-level hooks (termination + APNs).
///
/// Keep this thin. Scene-phase lifecycle is handled in ``TradeTraxsApp`` via
/// ``AppLifecycleHandler``. Push ownership lives in ``PushNotificationCenter``.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set immediately after composition so termination can be forwarded.
    var lifecycle: AppLifecycleHandler?
    /// Centralized APNs — features never register themselves.
    var pushNotifications: PushNotificationCenter?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Prefer the edge-anchored tab bar presentation over the floating capsule
        // when the OS still exposes that preference (iPad historically; harmless on iPhone).
        UserDefaults.standard.register(defaults: ["UseFloatingTabBar": false])
        AppLog.application.info("AppDelegate.didFinishLaunching")
        pushNotifications?.bindIfNeeded()

        if let remote = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            // Cold-start tap is also delivered via UNUserNotificationCenterDelegate;
            // keep a breadcrumb for diagnostics only.
            AppLog.notifications.info("Launch via remote notification")
            _ = remote
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        pushNotifications?.applicationDidRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pushNotifications?.applicationDidFailToRegisterForRemoteNotifications(error: error)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        pushNotifications?.handleForegroundRemoteNotification(userInfo: userInfo)
        completionHandler(.newData)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        lifecycle?.applicationWillTerminate()
    }
}
