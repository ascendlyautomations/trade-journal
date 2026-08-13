import Foundation

/// Process-wide application environment assembled at launch.
///
/// Owns configuration + the dependency graph. Features receive slices via
/// initializer injection; SwiftUI may observe this value through
/// ``EnvironmentValues/appEnvironment``.
struct AppEnvironment {
    let configuration: AppConfiguration
    let featureFlags: FeatureFlags
    let dependencies: DependencyContainer
    let lifecycle: AppLifecycleHandler
    let themeManager: ThemeManager
    /// Session-scoped authenticated profile cache (header + tab avatar).
    let currentUserProfile: CurrentUserProfileStore
    /// Centralized APNs registration + notification routing.
    let pushNotifications: PushNotificationCenter

    /// Convenience access: CompositionRoot → AppEnvironment → DependencyContainer → Navigation
    var navigation: NavigationEnvironment { dependencies.navigation }

    /// Convenience access: CompositionRoot → AppEnvironment → DependencyContainer → Networking
    var networking: NetworkingEnvironment { dependencies.networking }

    /// Convenience access: CompositionRoot → AppEnvironment → DependencyContainer → Data
    var data: DataEnvironment { dependencies.data }

    /// Convenience access: CompositionRoot → AppEnvironment → DependencyContainer → Authentication
    var authentication: AuthenticationEnvironment { dependencies.authentication }
}
