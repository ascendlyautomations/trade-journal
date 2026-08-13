import Foundation

/// Lightweight on-disk session presentation cache (Codable JSON).
///
/// GRDB is not yet a project dependency — this fills the persistence seam for
/// cold-launch reuse of accounts / following IDs / recent owner trades without
/// storing secrets. Cleared on logout.
enum SessionDiskCache {
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
    }

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

    static func saveOwnerTrades(_ trades: [Trade], for profileID: ProfileID) {
        // Cap disk footprint — presentation/recent window only.
        let capped = Array(trades.prefix(200))
        let blob = OwnerTradesBlob(profileID: profileID.rawValue, savedAt: Date(), trades: capped)
        write(blob, file: "owner-trades-\(profileID.rawValue).json")
    }

    static func loadOwnerTrades(for profileID: ProfileID, maxAge: TimeInterval = 6 * 60 * 60) -> [Trade]? {
        guard let blob: OwnerTradesBlob = read(file: "owner-trades-\(profileID.rawValue).json") else { return nil }
        guard Date().timeIntervalSince(blob.savedAt) <= maxAge else { return nil }
        return blob.trades
    }

    static func clearAll() {
        guard let dir = directoryURL() else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - IO

    private static func directoryURL() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func write<T: Encodable>(_ value: T, file: String) {
        guard let dir = directoryURL() else { return }
        let url = dir.appendingPathComponent(sanitize(file))
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Soft-fail — disk cache must never break networking.
        }
    }

    private static func read<T: Decodable>(file: String) -> T? {
        guard let dir = directoryURL() else { return nil }
        let url = dir.appendingPathComponent(sanitize(file))
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
    }
}
