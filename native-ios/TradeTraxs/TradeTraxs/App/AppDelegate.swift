import OSLog
import UIKit

/// UIKit application delegate for process-level hooks (termination, later: push).
///
/// Keep this thin. Scene-phase lifecycle is handled in ``TradeTraxsApp`` via
/// ``AppLifecycleHandler``.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set immediately after composition so termination can be forwarded.
    var lifecycle: AppLifecycleHandler?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppLog.application.info("AppDelegate.didFinishLaunching")
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        lifecycle?.applicationWillTerminate()
    }
}
