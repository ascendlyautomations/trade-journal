import Foundation

nonisolated struct EntitlementSnapshotRecord: Codable, Equatable, Sendable {
    var userID: String
    var traxProActive: Bool
    var source: String
    var accessExpiresAt: Date?
    var revokedAt: Date?
    var fetchedAt: Date
}

nonisolated enum EntitlementCacheDecision: Equatable, Sendable {
    /// Last verified snapshot still grants Pro.
    case grant
    /// Server snapshot says free, or expiry/revocation is already known.
    case deny
    /// No snapshot, or a non-expiring grant is older than the offline grace window.
    case unavailable
}

nonisolated enum EntitlementSnapshotPolicy {
    /// Manual, creator, and launch grants have no Apple/Stripe expiry. Do not keep them forever offline.
    static let nonExpiringOfflineGrace: TimeInterval = 7 * 24 * 60 * 60

    static func decision(
        _ record: EntitlementSnapshotRecord?,
        now: Date = Date()
    ) -> EntitlementCacheDecision {
        guard let record else { return .unavailable }
        if record.revokedAt != nil { return .deny }
        if !record.traxProActive { return .deny }
        if let expiresAt = record.accessExpiresAt {
            return expiresAt > now ? .grant : .deny
        }
        if now < record.fetchedAt.addingTimeInterval(nonExpiringOfflineGrace) {
            return .grant
        }
        return .unavailable
    }
}

nonisolated enum PersistedEntitlementSnapshotStore {
    static func cacheKey(userID: String) -> String {
        "tradetraxs.entitlement.snapshot.\(userID)"
    }

    static func save(_ record: EntitlementSnapshotRecord, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: cacheKey(userID: record.userID))
    }

    static func load(userID: String, defaults: UserDefaults = .standard) -> EntitlementSnapshotRecord? {
        guard let data = defaults.data(forKey: cacheKey(userID: userID)) else { return nil }
        return try? JSONDecoder().decode(EntitlementSnapshotRecord.self, from: data)
    }

    static func clear(userID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: cacheKey(userID: userID))
    }
}
