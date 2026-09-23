import Foundation
import GRDB

/// Opens and migrates the analytical SQLite database (background-friendly).
actor AnalyticsDatabase {
    static let shared = AnalyticsDatabase()

    struct Configuration: Sendable {
        var databaseURL: URL?

        static let production = Configuration()

        static func testing(databaseURL: URL) -> Configuration {
            Configuration(databaseURL: databaseURL)
        }
    }

    private let configuration: Configuration
    private var queue: DatabaseQueue?
    private var opening: Task<DatabaseQueue, Error>?

    init(configuration: Configuration = .production) {
        self.configuration = configuration
    }

    func databaseQueue() async throws -> DatabaseQueue {
        if let queue {
            return queue
        }
        if let opening {
            return try await opening.value
        }
        let task = Task { try await self.openQueue() }
        opening = task
        defer { opening = nil }
        let opened = try await task.value
        queue = opened
        return opened
    }

    func databaseFileBytes() async -> Int64 {
        let estimate = await storageByteEstimate()
        return estimate.sqliteBytes
    }

    func storageByteEstimate() async -> (sqliteBytes: Int64, walBytes: Int64) {
        guard let url = resolvedDatabaseURL() else { return (0, 0) }
        let sqlite = fileBytes(at: url)
        let wal = fileBytes(at: URL(fileURLWithPath: url.path + "-wal"))
        AnalyticsGRDBProbe.logStorageEstimate(sqliteBytes: sqlite, walBytes: wal)
        return (sqlite, wal)
    }

    private func fileBytes(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber
        else { return 0 }
        return size.int64Value
    }

    func resetForTests() {
        queue = nil
        opening = nil
    }

    private func openQueue() async throws -> DatabaseQueue {
        let started = Date()
        let url = try ensureDatabaseURL()
        let queue = try DatabaseQueue(path: url.path)
        let migrateStarted = Date()
        try migrate(queue)
        let migrateMs = Int(Date().timeIntervalSince(migrateStarted) * 1000)
        AnalyticsGRDBProbe.logMigration(elapsedMs: migrateMs)
        let openMs = Int(Date().timeIntervalSince(started) * 1000)
        AnalyticsGRDBProbe.logOpen(elapsedMs: openMs)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        AnalyticsGRDBProbe.logDatabaseBytes(bytes)
        return queue
    }

    private func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_analytical_foundation") { db in
            try db.execute(sql: AnalyticsLocalSchema.createSyncState)
            try db.execute(sql: AnalyticsLocalSchema.createDailyStat)
            try db.execute(sql: AnalyticsLocalSchema.createDailyStatDayIndex)
            try db.execute(sql: AnalyticsLocalSchema.createCoverage)
        }
        migrator.registerMigration("v2_dashboard_shadow") { db in
            try db.execute(sql: AnalyticsLocalSchema.createDashboardPresetMetrics)
            try db.execute(sql: AnalyticsLocalSchema.createDashboardPresetIndex)
            try db.execute(sql: AnalyticsLocalSchema.createDashboardChartBundle)
            try db.execute(sql: AnalyticsLocalSchema.createDashboardChartIndex)
        }
        migrator.registerMigration("v3_profile_analytics") { db in
            try db.execute(sql: AnalyticsLocalSchema.createProfileAnalyticsSnapshot)
            try db.execute(sql: AnalyticsLocalSchema.createProfileAnalyticsSnapshotIndex)
        }
        try migrator.migrate(queue)
    }

    private func ensureDatabaseURL() throws -> URL {
        if let url = configuration.databaseURL {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return url
        }
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AnalyticsDatabaseError.applicationSupportUnavailable
        }
        let dir = support
            .appendingPathComponent("TradeTraxs", isDirectory: true)
            .appendingPathComponent("Analytics", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("TradeTraxsAnalytics.sqlite")
    }

    private func resolvedDatabaseURL() -> URL? {
        if let url = configuration.databaseURL {
            return url
        }
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return support
            .appendingPathComponent("TradeTraxs/Analytics/TradeTraxsAnalytics.sqlite")
    }
}

nonisolated enum AnalyticsDatabaseError: Error {
    case applicationSupportUnavailable
}
