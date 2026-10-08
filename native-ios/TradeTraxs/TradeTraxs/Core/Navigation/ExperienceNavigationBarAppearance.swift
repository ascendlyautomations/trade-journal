import SwiftUI
import UIKit

/// Process-wide navigation bar back control — chevron only, no previous-page title.
enum ExperienceNavigationBarAppearance {
    /// Mirrored by ``MainTabShellView`` — drives ``syncShellBarChrome()`` on tab/theme changes.
    nonisolated(unsafe) static var usesFeedOpaqueChrome = false

    /// Set only by ``DashboardHomeView`` while the Dashboard root is visible (Home tab, empty path).
    nonisolated(unsafe) static var dashboardScrollHeaderOpaqueNavBarActive = false

    static func configureArrowOnlyBackButtons() {
        // Hides the previous screen title beside the system back chevron on pushed pages.
        let hiddenTitleOffset = UIOffset(horizontal: -1000, vertical: 0)
        UIBarButtonItem.appearance().setBackButtonTitlePositionAdjustment(
            hiddenTitleOffset,
            for: .default
        )
    }

    /// Non-Feed shell chrome — semantic ``navigationBackground`` / ``tabBarBackground`` (pre-opacity SwiftUI parity).
    ///
    /// Do not use `configureWithDefaultBackground()`; system bar material reads warm brown/tan in dark mode.
    static func configureDefaultBarChrome(colors: SemanticColorPalette = ThemePaletteAnchor.current) {
        let background = UIColor(colors.navigationBackground)

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = background

        let navigationBar = UINavigationBar.appearance()
        navigationBar.isTranslucent = true
        navigationBar.standardAppearance = navigation
        navigationBar.scrollEdgeAppearance = navigation
        navigationBar.compactAppearance = navigation
        if #available(iOS 15.0, *) {
            navigationBar.compactScrollEdgeAppearance = navigation
        }

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = background

        let tabBar = UITabBar.appearance()
        tabBar.isTranslucent = true
        tabBar.standardAppearance = tab
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = tab
        }
    }

    static func syncShellBarChrome(colors: SemanticColorPalette = ThemePaletteAnchor.current) {
        if usesFeedOpaqueChrome || dashboardScrollHeaderOpaqueNavBarActive {
            configureOpaqueBarChrome(colors: colors)
        } else {
            configureDefaultBarChrome(colors: colors)
        }
        ExperienceGroupedListAppearance.sync(colors: colors)
    }

    /// Opaque nav bar (`isTranslucent = false`) — Feed tab and Dashboard scroll-header experiment.
    /// Uses the same ``SemanticColorPalette/navigationBackground`` as default Home chrome.
    static func configureOpaqueBarChrome(colors: SemanticColorPalette = ThemePaletteAnchor.current) {
        let background = UIColor(colors.navigationBackground)

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = background

        let navigationBar = UINavigationBar.appearance()
        navigationBar.isTranslucent = false
        navigationBar.standardAppearance = navigation
        navigationBar.scrollEdgeAppearance = navigation
        navigationBar.compactAppearance = navigation
        if #available(iOS 15.0, *) {
            navigationBar.compactScrollEdgeAppearance = navigation
        }

        // Tab bar: opaque fill via appearance only — do NOT set `isTranslucent = false`.
        // SwiftUI `TabView` keeps compact item layout when the bar stays translucent;
        // `isTranslucent = false` reserves the home-indicator inset as empty bar height
        // above the icons (regression). SwiftUI `toolbarBackground` on MainTabShellView
        // also paints the tab surface.
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = background

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tab
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = tab
        }
    }
}

/// Process-wide UITableView / UICollectionView defaults for SwiftUI `List`.
///
/// System grouped list fills read warm brown in dark mode until TradeTraxs theme modifiers paint;
/// syncing appearance at launch and on theme changes avoids a first-frame flash.
enum ExperienceGroupedListAppearance {
    static func sync(colors: SemanticColorPalette = ThemePaletteAnchor.current) {
        let page = UIColor(colors.backgroundPrimary)
        let separator = UIColor(colors.separator)

        UITableView.appearance().backgroundColor = page
        UICollectionView.appearance().backgroundColor = page
        UITableView.appearance().separatorColor = separator
    }
}
