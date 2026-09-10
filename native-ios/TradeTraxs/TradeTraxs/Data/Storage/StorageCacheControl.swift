import Foundation

/// Immutable media objects use timestamped storage paths — safe for long CDN/browser cache.
nonisolated enum StorageCacheControl {
    static let immutableMaxAge = "31536000"
}
