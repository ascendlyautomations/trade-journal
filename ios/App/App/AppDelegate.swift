import UIKit
import Capacitor

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        return true
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

    // TEMPORARY: kept for when Push Notifications entitlement is restored.
    // Harmless without aps-environment (registration simply fails / is skipped in JS).
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
