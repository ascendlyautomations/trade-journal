import Foundation

/// Catalog of available themes. Register future themes without engine changes.
final class ThemeRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var themes: [ThemeIdentifier: any AppThemeProtocol]

    init(builtIns: [any AppThemeProtocol] = ThemeRegistry.defaultBuiltIns) {
        var map: [ThemeIdentifier: any AppThemeProtocol] = [:]
        for theme in builtIns {
            map[theme.metadata.identifier] = theme
        }
        self.themes = map
    }

    static var defaultBuiltIns: [any AppThemeProtocol] {
        [
            SystemTheme(),
            LightTheme(),
            DarkTheme(),
            TradeTraxsTheme(),
        ]
    }

    func theme(for identifier: ThemeIdentifier) -> (any AppThemeProtocol)? {
        lock.lock(); defer { lock.unlock() }
        return themes[identifier]
    }

    func register(_ theme: any AppThemeProtocol) {
        lock.lock()
        themes[theme.metadata.identifier] = theme
        lock.unlock()
    }

    func allMetadata() -> [ThemeMetadata] {
        lock.lock(); defer { lock.unlock() }
        let order: [ThemeIdentifier] = [.system, .light, .dark, .tradeTraxs]
        var result: [ThemeMetadata] = []
        for id in order {
            if let theme = themes[id] {
                result.append(theme.metadata)
            }
        }
        let extras = themes.keys.filter { !order.contains($0) }.sorted { $0.rawValue < $1.rawValue }
        for id in extras {
            if let theme = themes[id] {
                result.append(theme.metadata)
            }
        }
        return result
    }
}
