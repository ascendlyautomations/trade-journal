import Foundation

/// JSON disk cache for successful Backend V2 bootstrap payloads (no GRDB).
nonisolated enum BackendV2BootstrapDiskCache {
    private static let folderName = "BackendV2BootstrapCache"
    private static let softStaleSeconds: TimeInterval = 10 * 60
    private static let hardExpirySeconds: TimeInterval = 24 * 60 * 60

    struct SessionBlob: Codable, Sendable {
        var viewerID: String
        var contractVersion: String
        var savedAt: Date
        var bootstrap: SessionBootstrapV1
    }

    struct DashboardBlob: Codable, Sendable {
        var viewerID: String
        var accountScope: String
        var contractVersion: String
        var savedAt: Date
        var bootstrap: DashboardBootstrapV1
    }

    enum Freshness: Sendable {
        case fresh
        case softStale
        case expired
    }

    // MARK: - Session

    static func saveSession(_ bootstrap: SessionBootstrapV1, viewerID: String) {
        let blob = SessionBlob(
            viewerID: viewerID,
            contractVersion: bootstrap.meta.contract_version,
            savedAt: Date(),
            bootstrap: bootstrap
        )
        write(blob, file: sessionFile(viewerID: viewerID))
    }

    static func loadSession(viewerID: String) -> (bootstrap: SessionBootstrapV1, freshness: Freshness)? {
        guard let blob: SessionBlob = read(file: sessionFile(viewerID: viewerID)) else { return nil }
        guard blob.viewerID == viewerID else { return nil }
        guard blob.contractVersion == BackendV2Versioning.contractVersion else { return nil }
        let age = Date().timeIntervalSince(blob.savedAt)
        if age > hardExpirySeconds { return nil }
        let freshness: Freshness = age <= softStaleSeconds ? .fresh : .softStale
        return (blob.bootstrap, freshness)
    }

    // MARK: - Dashboard

    static func saveDashboard(
        _ bootstrap: DashboardBootstrapV1,
        viewerID: String,
        accountScope: String = "all"
    ) {
        let blob = DashboardBlob(
            viewerID: viewerID,
            accountScope: accountScope,
            contractVersion: bootstrap.meta.contract_version,
            savedAt: Date(),
            bootstrap: bootstrap
        )
        write(blob, file: dashboardFile(viewerID: viewerID, accountScope: accountScope))
    }

    static func loadDashboard(
        viewerID: String,
        accountScope: String = "all"
    ) -> (bootstrap: DashboardBootstrapV1, freshness: Freshness)? {
        guard let blob: DashboardBlob = read(file: dashboardFile(viewerID: viewerID, accountScope: accountScope))
        else { return nil }
        guard blob.viewerID == viewerID, blob.accountScope == accountScope else { return nil }
        guard blob.contractVersion == BackendV2Versioning.contractVersion else { return nil }
        let age = Date().timeIntervalSince(blob.savedAt)
        if age > hardExpirySeconds { return nil }
        let freshness: Freshness = age <= softStaleSeconds ? .fresh : .softStale
        return (blob.bootstrap, freshness)
    }

    static func clearAll(viewerID: String? = nil) {
        guard let dir = directoryURL() else { return }
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for url in contents {
            if let viewerID {
                let name = url.lastPathComponent
                if name.contains(viewerID) {
                    try? FileManager.default.removeItem(at: url)
                }
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Replace one trade row inside a cached dashboard bootstrap payload (Edit Trade / create upsert).
    static func patchTrade(_ trade: Trade, viewerID: String, accountScope: String = "all") {
        guard var cached = loadMutableDashboard(viewerID: viewerID, accountScope: accountScope) else {
            return
        }
        let tradeID = trade.id.rawValue
        if let index = cached.bootstrap.data.trade_window.firstIndex(where: { $0.id == tradeID }) {
            cached.bootstrap.data.trade_window[index].mergeJournalFields(from: trade)
        } else {
            cached.bootstrap.data.trade_window.insert(trade.asDashboardWireV1(), at: 0)
        }
        cached.savedAt = Date()
        write(cached, file: dashboardFile(viewerID: viewerID, accountScope: accountScope))
    }

    /// Remove a deleted trade from cached dashboard bootstrap payloads.
    static func removeTrade(id tradeID: String, viewerID: String, accountScope: String = "all") {
        guard var cached = loadMutableDashboard(viewerID: viewerID, accountScope: accountScope) else {
            return
        }
        let before = cached.bootstrap.data.trade_window.count
        cached.bootstrap.data.trade_window.removeAll { $0.id == tradeID }
        guard cached.bootstrap.data.trade_window.count != before else { return }
        cached.savedAt = Date()
        write(cached, file: dashboardFile(viewerID: viewerID, accountScope: accountScope))
    }

    private static func loadMutableDashboard(
        viewerID: String,
        accountScope: String
    ) -> DashboardBlob? {
        read(file: dashboardFile(viewerID: viewerID, accountScope: accountScope))
    }

    // MARK: - IO

    private static func sessionFile(viewerID: String) -> String {
        "session-\(viewerID).json"
    }

    private static func dashboardFile(viewerID: String, accountScope: String) -> String {
        "dashboard-\(viewerID)-\(accountScope).json"
    }

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
        let url = dir.appendingPathComponent(file)
        let temp = dir.appendingPathComponent("\(file).tmp")
        guard let data = try? JSONEncoder().encode(value) else { return }
        do {
            try data.write(to: temp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: temp, to: url)
        } catch {
            try? FileManager.default.removeItem(at: temp)
        }
    }

    private static func read<T: Decodable>(file: String) -> T? {
        guard let dir = directoryURL() else { return nil }
        let url = dir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
