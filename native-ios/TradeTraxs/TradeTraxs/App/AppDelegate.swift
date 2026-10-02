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

    override init() {
        StartupTrace.begin("AppDelegate.init")
        super.init()
        StartupTrace.end("AppDelegate.init")
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Prefer the edge-anchored tab bar presentation over the floating capsule
        // when the OS still exposes that preference (iPad historically; harmless on iPhone).
        UserDefaults.standard.register(defaults: ["UseFloatingTabBar": false])
        ExperienceNavigationBarAppearance.configureArrowOnlyBackButtons()
        ExperienceNavigationBarAppearance.configureDefaultBarChrome()
        ExperienceGroupedListAppearance.sync()
        StartupTrace.event("AppDelegate.didFinishLaunching")
        AppLog.application.info("AppDelegate.didFinishLaunching")
        // The notification-center delegate must exist before launch returns.
        // SwiftUI onAppear is too late for a cold-start tap.
        if pushNotifications == nil {
            let environment = AppLaunchController.shared.environment
            pushNotifications = environment.pushNotifications
            lifecycle = environment.lifecycle
            environment.lifecycle.pushNotifications = environment.pushNotifications
        }
        pushNotifications?.bindIfNeeded()

        if let url = launchOptions?[.url] as? URL {
            LaunchUniversalLinkInbox.capture(url)
        }
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

    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        _ = options
        LaunchUniversalLinkInbox.capture(url)
        return false
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        _ = restorationHandler
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
            LaunchUniversalLinkInbox.capture(url)
        }
        return false
    }

    func applicationWillTerminate(_ application: UIApplication) {
        lifecycle?.applicationWillTerminate()
    }
}
