import Foundation

/// Process-wide production ``AppEnvironment`` — created at most once per launch.
///
/// SwiftUI may read ``EnvironmentKey/defaultValue`` on every view refresh. That
/// path must never call ``CompositionRoot/bootstrap()`` directly or the entire
/// dependency graph is rebuilt in a loop (black screen + repeated ready logs).
enum AppLaunchEnvironment {
    static var shared: AppEnvironment {
        MainActor.assumeIsolated {
            AppLaunchController.shared.environment
        }
    }
}
