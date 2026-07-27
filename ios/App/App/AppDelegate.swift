import UIKit
import UserNotifications
import Capacitor

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Match LaunchScreen / Capacitor backgroundColor (#0b1f3a) so the handoff
        // from the static launch image into the WebView never flashes white/black.
        let launchBackground = UIColor(
            red: 11.0 / 255.0,
            green: 31.0 / 255.0,
            blue: 58.0 / 255.0,
            alpha: 1.0
        )
        window?.backgroundColor = launchBackground
        window?.tintColor = launchBackground

        registerTradeTraxsNotificationCategories()
        return true
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
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Do not reload or re-navigate. Resume in place.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Do not reload or re-navigate. Resume in place.
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
        NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
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
