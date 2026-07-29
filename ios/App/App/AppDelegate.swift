import UIKit
import UserNotifications
import Capacitor

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Match LaunchScreen / Capacitor backgroundColor (#0b1f3a).
        let launchBackground = TradeTraxsLaunchSplash.shellBackground
        window?.backgroundColor = launchBackground
        window?.tintColor = launchBackground

        // Install the Splash cover on the window BEFORE the first app frame so
        // the system LaunchScreen hands off to the same image — never to the
        // empty navy WebView shell. TradeTraxsBridgeViewController dismisses it
        // once login/dashboard has a meaningful painted frame.
        if let window {
            TradeTraxsLaunchSplash.install(on: window)
        }

        registerTradeTraxsNotificationCategories()

        // TEMPORARY [tt-push-debug] — remove after delivery diagnosis.
        TradeTraxsPushDebug.logNotificationSettings(reason: "didFinishLaunching")
        // Capacitor sets UNUserNotificationCenter.delegate during plugin load;
        // retry wrapping so we log without replacing presentation behavior.
        schedulePushDebugDelegateInstall()

        return true
    }

    /// Portrait-only for the entire native shell (Info.plist + this mask).
    /// System camera / photo pickers may still present briefly; after dismiss
    /// the app returns to portrait because landscape is not a supported mask.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }

    /// TEMPORARY [tt-push-debug]
    private func schedulePushDebugDelegateInstall() {
        let delays: [TimeInterval] = [0.3, 1.0, 2.0, 5.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                TradeTraxsPushDebug.installDelegateWrapper()
            }
        }
    }

    /// Long-press actions for remote pushes (category must match APNs `aps.category`).
    private func registerTradeTraxsNotificationCategories() {
        let reply = UNTextInputNotificationAction(
            identifier: "TT_REPLY",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Message"
        )
        let markRead = UNNotificationAction(
            identifier: "TT_MARK_READ",
            title: "Mark as Read",
            options: []
        )
        let openRoom = UNNotificationAction(
            identifier: "TT_OPEN_ROOM",
            title: "Open Room",
            options: [.foreground]
        )
        let viewComment = UNNotificationAction(
            identifier: "TT_VIEW_COMMENT",
            title: "View Comment",
            options: [.foreground]
        )
        let acceptFollow = UNNotificationAction(
            identifier: "TT_ACCEPT_FOLLOW",
            title: "Accept",
            options: [.foreground]
        )
        let declineFollow = UNNotificationAction(
            identifier: "TT_DECLINE_FOLLOW",
            title: "Decline",
            options: [.destructive]
        )

        let dm = UNNotificationCategory(
            identifier: "TT_DM",
            actions: [reply, markRead],
            intentIdentifiers: [],
            options: []
        )
        let room = UNNotificationCategory(
            identifier: "TT_ROOM",
            actions: [openRoom, markRead],
            intentIdentifiers: [],
            options: []
        )
        let comment = UNNotificationCategory(
            identifier: "TT_COMMENT",
            actions: [viewComment],
            intentIdentifiers: [],
            options: []
        )
        let followRequest = UNNotificationCategory(
            identifier: "TT_FOLLOW_REQUEST",
            actions: [acceptFollow, declineFollow],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            dm, room, comment, followRequest
        ])
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Control Center / Notification Center / brief multitasking.
        // Persist URL only — never reload the WebView here.
        persistWebViewUrlIfPossible()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        persistWebViewUrlIfPossible()
        // TEMPORARY [tt-push-debug]
        NSLog("%@ applicationDidEnterBackground timestamp=%@", TradeTraxsPushDebug.prefix, ISO8601DateFormatter().string(from: Date()))
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Do not reload or re-navigate. Resume in place.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Do not reload or re-navigate. Resume in place.

        // TEMPORARY [tt-push-debug] — re-wrap if Capacitor replaced the delegate.
        TradeTraxsPushDebug.installDelegateWrapper()
        TradeTraxsPushDebug.logNotificationSettings(reason: "didBecomeActive")
        TradeTraxsPushDebug.logDeliveredNotifications(reason: "didBecomeActive")
    }

    func applicationWillTerminate(_ application: UIApplication) {
        persistWebViewUrlIfPossible()
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Called when the app was launched with a url. Feel free to add additional processing here,
        // but if you want the App API to support tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Called when the app was launched with an activity, including Universal Links.
        // Feel free to add additional processing here, but if you want the App API to support
        // tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

    // Device token forwarding for @capacitor/push-notifications.
    // Registration only succeeds once aps-environment is present (see App.entitlements)
    // and Push Notifications is enabled on the App ID in Apple Developer.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // TEMPORARY [tt-push-debug]
        TradeTraxsPushDebug.logDeviceToken(deviceToken)
        NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // TEMPORARY [tt-push-debug]
        TradeTraxsPushDebug.logRegistrationFailure(error)
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
    }

    // TEMPORARY [tt-push-debug] — log silent/background delivery callbacks (alert pushes may not hit this).
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        TradeTraxsPushDebug.logRemoteNotification(
            source: "didReceiveRemoteNotification",
            userInfo: userInfo,
            fetchCompletion: completionHandler
        )
    }

    private func persistWebViewUrlIfPossible() {
        guard let bridgeVC = window?.rootViewController as? TradeTraxsBridgeViewController
                ?? window?.rootViewController?.children.first as? TradeTraxsBridgeViewController
        else {
            return
        }
        bridgeVC.persistWebViewUrl()
    }

}
