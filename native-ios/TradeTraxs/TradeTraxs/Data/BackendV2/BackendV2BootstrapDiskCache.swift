import Foundation

/// JSON disk cache for successful Backend V2 bootstrap payloads (no GRDB).
nonisolated enum BackendV2BootstrapDiskCache {
    private static let folderName = "BackendV2BootstrapCache"
    /// Authoritative freshness — onboarding and mutation gating.
    private static let softStaleSeconds: TimeInterval = 10 * 60
    private static let authoritativeMaxSeconds: TimeInterval = 24 * 60 * 60
    /// Render-only freshness — aligned with ``FeedDiskCache`` (7 days).
    static let displayMaxSeconds: TimeInterval = 7 * 24 * 60 * 60

    enum Freshness: Sendable {
        case fresh
        case softStale
        /// Older than authoritative max but still renderable (display-only).
        case displayOnly
        case expired

        var isAuthoritative: Bool {
            switch self {
            case .fresh, .softStale:
                return true
            case .displayOnly, .expired:
                return false
            }
        }

        var isRenderable: Bool {
            switch self {
            case .fresh, .softStale, .displayOnly:
                return true
            case .expired:
                return false
            }
        }
    }

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
        loadSessionBlob(viewerID: viewerID)
    }

    /// True when a renderable session bootstrap blob exists (includes display-only staleness).
    static func hasRenderableSession(viewerID: String) -> Bool {
        loadSession(viewerID: viewerID) != nil
    }

    private static func loadSessionBlob(viewerID: String) -> (bootstrap: SessionBootstrapV1, freshness: Freshness)? {
        guard let blob: SessionBlob = read(file: sessionFile(viewerID: viewerID)) else { return nil }
        guard blob.viewerID == viewerID else { return nil }
        guard blob.contractVersion == BackendV2Versioning.contractVersion else { return nil }
        guard let freshness = classifyAge(Date().timeIntervalSince(blob.savedAt)) else { return nil }
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
        loadDashboardBlob(viewerID: viewerID, accountScope: accountScope)
            .map { ($0.bootstrap, $0.freshness) }
    }

    private static func loadDashboardBlob(
        viewerID: String,
        accountScope: String
    ) -> (bootstrap: DashboardBootstrapV1, freshness: Freshness)? {
        guard let blob: DashboardBlob = read(file: dashboardFile(viewerID: viewerID, accountScope: accountScope))
        else { return nil }
        guard blob.viewerID == viewerID, blob.accountScope == accountScope else { return nil }
        guard blob.contractVersion == BackendV2Versioning.contractVersion else { return nil }
        guard let freshness = classifyAge(Date().timeIntervalSince(blob.savedAt)) else { return nil }
        return (blob.bootstrap, freshness)
    }

    private static func classifyAge(_ age: TimeInterval) -> Freshness? {
        if age > displayMaxSeconds { return nil }
        if age <= softStaleSeconds { return .fresh }
        if age <= authoritativeMaxSeconds { return .softStale }
        return .displayOnly
    }

    /// Promote soft-stale blobs to fresh without changing bootstrap payloads.
    static func touchSession(viewerID: String) {
        guard var blob: SessionBlob = read(file: sessionFile(viewerID: viewerID)) else { return }
        blob.savedAt = Date()
        write(blob, file: sessionFile(viewerID: viewerID))
    }

    static func touchDashboard(viewerID: String, accountScope: String = "all") {
        guard var blob: DashboardBlob = read(file: dashboardFile(viewerID: viewerID, accountScope: accountScope))
        else { return }
        blob.savedAt = Date()
        write(blob, file: dashboardFile(viewerID: viewerID, accountScope: accountScope))
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

    /// Replace the full accounts array inside a cached dashboard bootstrap payload.
    static func replaceAccounts(_ accounts: [TradingAccount], viewerID: String, accountScope: String = "all") {
        guard var cached = loadMutableDashboard(viewerID: viewerID, accountScope: accountScope) else {
            return
        }
        cached.bootstrap.data.accounts = accounts.map { $0.asDashboardWireV1() }
        cached.savedAt = Date()
        write(cached, file: dashboardFile(viewerID: viewerID, accountScope: accountScope))
    }

    /// Patch one account row inside a cached dashboard bootstrap payload.
    static func patchAccount(_ account: TradingAccount, viewerID: String, accountScope: String = "all") {
        guard var cached = loadMutableDashboard(viewerID: viewerID, accountScope: accountScope) else {
            return
        }
        let accountID = account.id.rawValue
        if let index = cached.bootstrap.data.accounts.firstIndex(where: { $0.id == accountID }) {
            cached.bootstrap.data.accounts[index].mergeFields(from: account)
        } else {
            cached.bootstrap.data.accounts.insert(account.asDashboardWireV1(), at: 0)
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
        PersistentAppDataDiskCache.directoryURL(component: folderName)
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
            DiskCacheIOProbe.recordWrite()
        } catch {
            try? FileManager.default.removeItem(at: temp)
        }
    }

    private static func read<T: Decodable>(file: String) -> T? {
        guard let dir = directoryURL() else { return nil }
        let url = dir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        DiskCacheIOProbe.recordRead()
        return try? JSONDecoder().decode(T.self, from: data)
    }

    #if DEBUG
    /// Force session + dashboard disk caches into soft-stale without changing production TTL constants.
    static func forceSoftStaleForTesting(viewerID: String, accountScope: String = "all") {
        let staleDate = Date().addingTimeInterval(-(11 * 60))
        if var session: SessionBlob = read(file: sessionFile(viewerID: viewerID)) {
            session.savedAt = staleDate
            write(session, file: sessionFile(viewerID: viewerID))
        }
        if var dashboard: DashboardBlob = read(file: dashboardFile(viewerID: viewerID, accountScope: accountScope)) {
            dashboard.savedAt = staleDate
            write(dashboard, file: dashboardFile(viewerID: viewerID, accountScope: accountScope))
        }
    }

    /// Test helper — write dashboard cache with an explicit saved-at for soft-stale simulation.
    static func saveDashboardForTesting(
        _ bootstrap: DashboardBootstrapV1,
        viewerID: String,
        accountScope: String = "all",
        savedAt: Date
    ) {
        let blob = DashboardBlob(
            viewerID: viewerID,
            accountScope: accountScope,
            contractVersion: bootstrap.meta.contract_version,
            savedAt: savedAt,
            bootstrap: bootstrap
        )
        write(blob, file: dashboardFile(viewerID: viewerID, accountScope: accountScope))
    }

    static func saveSessionForTesting(
        _ bootstrap: SessionBootstrapV1,
        viewerID: String,
        savedAt: Date
    ) {
        let blob = SessionBlob(
            viewerID: viewerID,
            contractVersion: bootstrap.meta.contract_version,
            savedAt: savedAt,
            bootstrap: bootstrap
        )
        write(blob, file: sessionFile(viewerID: viewerID))
    }
    #endif
}
