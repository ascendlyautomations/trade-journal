import Foundation

/// Launch / runtime theme engine knobs.
struct ThemeConfiguration: Sendable, Equatable {
    /// Default when no preference is stored.
    var defaultTheme: ThemeIdentifier
    /// Animate theme switches with Experience motion.
    var animatesTransitions: Bool

    static let `default` = ThemeConfiguration(
        defaultTheme: .system,
        animatesTransitions: true
    )
}
