import Foundation

/// Future iPad split-column preferences.
///
/// v1 phone uses single-column stacks. iPad can adopt `NavigationSplitView`
/// without changing ``AppDestination`` or tab identity.
struct SplitNavigationConfiguration: Codable, Hashable, Sendable {
    /// Preferred secondary column visibility on regular width.
    var prefersSideBySide: Bool
    /// Which tab may use split (Messages list+thread, etc.).
    var enabledTabs: Set<TabIdentifier>

    static let phone = SplitNavigationConfiguration(
        prefersSideBySide: false,
        enabledTabs: []
    )

    static let padDefault = SplitNavigationConfiguration(
        prefersSideBySide: true,
        enabledTabs: [.messages, .home]
    )
}

/// Abstraction for column-aware presentation decisions.
protocol SplitNavigationSupporting: Sendable {
    var configuration: SplitNavigationConfiguration { get }
    func usesSplit(for tab: TabIdentifier, horizontalSizeClassIsRegular: Bool) -> Bool
}

struct SplitNavigationSupport: SplitNavigationSupporting {
    let configuration: SplitNavigationConfiguration

    init(configuration: SplitNavigationConfiguration = .phone) {
        self.configuration = configuration
    }

    func usesSplit(for tab: TabIdentifier, horizontalSizeClassIsRegular: Bool) -> Bool {
        horizontalSizeClassIsRegular
            && configuration.prefersSideBySide
            && configuration.enabledTabs.contains(tab)
    }
}
