import Foundation

/// Lightweight on-disk session presentation cache (Codable JSON).
///
/// GRDB is not yet a project dependency — this fills the persistence seam for
/// cold-launch reuse of accounts / following IDs / recent owner trades without
/// storing secrets. Cleared on logout.
nonisolated enum SessionDiskCache {
    private static let folderName = "SessionDiskCache"

    struct AccountsBlob: Codable, Sendable {
        var profileID: String
        var savedAt: Date
        var accounts: [TradingAccount]
    }

    struct FollowingBlob: Codable, Sendable {
        var viewerID: String
        var savedAt: Date
        var followingIDs: [String]
    }

    struct OwnerTradesBlob: Codable, Sendable {
        var profileID: String
        var savedAt: Date
        var trades: [Trade]
        var historyComplete: Bool?
        var totalTradeCount: Int?
    }

    /// Align with dashboard trade window — single owner snapshot, not a second trade database.
    static let ownerTradesMaxCount = 500
    static let ownerTradesMaxAge: TimeInterval = 7 * 24 * 60 * 60

    static func saveAccounts(_ accounts: [TradingAccount], for profileID: ProfileID) {
        let blob = AccountsBlob(profileID: profileID.rawValue, savedAt: Date(), accounts: accounts)
        write(blob, file: "accounts-\(profileID.rawValue).json")
    }

    static func loadAccounts(for profileID: ProfileID, maxAge: TimeInterval = 24 * 60 * 60) -> [TradingAccount]? {
        guard let blob: AccountsBlob = read(file: "accounts-\(profileID.rawValue).json") else { return nil }
        guard Date().timeIntervalSince(blob.savedAt) <= maxAge else { return nil }
        return blob.accounts
    }

    static func saveFollowing(ids: [String], for viewerID: ProfileID) {
        let blob = FollowingBlob(viewerID: viewerID.rawValue, savedAt: Date(), followingIDs: ids)
        write(blob, file: "following-\(viewerID.rawValue).json")
    }

    static func loadFollowing(for viewerID: ProfileID, maxAge: TimeInterval = 6 * 60 * 60) -> [String]? {
        guard let blob: FollowingBlob = read(file: "following-\(viewerID.rawValue).json") else { return nil }
        guard Date().timeIntervalSince(blob.savedAt) <= maxAge else { return nil }
        return blob.followingIDs
    }

    static func saveOwnerTrades(
        _ trades: [Trade],
        for profileID: ProfileID,
        historyComplete: Bool? = nil,
        totalTradeCount: Int? = nil
    ) {
        let capped = Array(trades.prefix(ownerTradesMaxCount))
        let blob = OwnerTradesBlob(
            profileID: profileID.rawValue,
            savedAt: Date(),
            trades: capped,
            historyComplete: historyComplete,
            totalTradeCount: totalTradeCount
        )
        write(blob, file: "owner-trades-\(profileID.rawValue).json")
    }

    static func loadOwnerTrades(
        for profileID: ProfileID,
        maxAge: TimeInterval = ownerTradesMaxAge
    ) -> OwnerTradesBlob? {
        guard let blob: OwnerTradesBlob = read(file: "owner-trades-\(profileID.rawValue).json") else {
            return nil
        }
        guard Date().timeIntervalSince(blob.savedAt) <= maxAge else { return nil }
        guard blob.profileID == profileID.rawValue else { return nil }
        return blob
    }

    static func clearAll() {
        guard let dir = directoryURL() else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - IO

    private static func directoryURL() -> URL? {
        PersistentAppDataDiskCache.directoryURL(component: folderName)
    }

    private static func write<T: Encodable>(_ value: T, file: String) {
        guard let dir = directoryURL() else { return }
        let url = dir.appendingPathComponent(sanitize(file))
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
            DiskCacheIOProbe.recordWrite()
        } catch {
            // Soft-fail — disk cache must never break networking.
        }
    }

    private static func read<T: Decodable>(file: String) -> T? {
        guard let dir = directoryURL() else { return nil }
        let url = dir.appendingPathComponent(sanitize(file))
        guard let data = try? Data(contentsOf: url) else { return nil }
        DiskCacheIOProbe.recordRead()
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
    }
}
