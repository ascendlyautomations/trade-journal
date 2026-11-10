import Foundation

/// Owner journal Trades screen — grid/list preference (separate from Profile tab persistence).
enum TradeHistoryBrowseLayoutStore {
    private static let key = "journal.trades.browseLayout"

    static func layout() -> ProfileBrowseLayout {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        return ProfileBrowseLayout(rawValue: raw) ?? .list
    }

    static func save(_ layout: ProfileBrowseLayout) {
        UserDefaults.standard.set(layout.rawValue, forKey: key)
    }
}
