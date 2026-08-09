import Foundation

/// Process-wide production ``AppEnvironment`` — created at most once per launch.
///
/// SwiftUI may read ``EnvironmentKey/defaultValue`` on every view refresh. That
/// path must never call ``CompositionRoot/bootstrap()`` directly or the entire
/// dependency graph is rebuilt in a loop (black screen + repeated ready logs).
enum AppLaunchEnvironment {
    private static let lock = NSLock()
    private static var cached: AppEnvironment?

    static var shared: AppEnvironment {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let environment = CompositionRoot.bootstrap()
        cached = environment
        return environment
    }
}
