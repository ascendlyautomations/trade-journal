import Foundation

nonisolated struct CachedMonetizationFlags: Codable, Equatable, Sendable {
    var iosPaywallEnabled: Bool
    var entitlementEnforcementEnabled: Bool
}

extension Notification.Name {
    nonisolated static let monetizationConfigurationDidChange = Notification.Name("monetizationConfigurationDidChange")
}

/// Last successful server flags for the signed-in user. Defaults are false.
/// Lock-protected so Settings and billing can read it off the main actor.
nonisolated final class MonetizationRuntimeConfiguration: @unchecked Sendable {
    static let shared = MonetizationRuntimeConfiguration()

    private let lock = NSLock()
    private var paywall = false
    private var enforcement = false
    private var activeUserID: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var iosPaywallEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return paywall
    }

    var entitlementEnforcementEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enforcement
    }

    func resetToFailClosed() {
        lock.lock()
        paywall = false
        enforcement = false
        activeUserID = nil
        lock.unlock()
        notifyChange()
    }

    /// Loads this user's last successful config. No cache stays false.
    func restoreCache(userID: String) {
        let cached = Self.load(userID: userID, defaults: defaults)
        lock.lock()
        activeUserID = userID
        paywall = cached?.iosPaywallEnabled ?? false
        enforcement = cached?.entitlementEnforcementEnabled ?? false
        lock.unlock()
        notifyChange()
    }

    /// Applies a decoded server response. Malformed callers must not call this.
    func applySuccessfulFetch(_ flags: CachedMonetizationFlags, userID: String) {
        lock.lock()
        guard activeUserID == userID || activeUserID == nil else {
            lock.unlock()
            return
        }
        activeUserID = userID
        paywall = flags.iosPaywallEnabled
        enforcement = flags.entitlementEnforcementEnabled
        lock.unlock()
        Self.save(flags, userID: userID, defaults: defaults)
        notifyChange()
    }

    static func cacheKey(userID: String) -> String {
        "tradetraxs.monetization.config.\(userID)"
    }

    static func load(userID: String, defaults: UserDefaults) -> CachedMonetizationFlags? {
        guard let data = defaults.data(forKey: cacheKey(userID: userID)) else { return nil }
        return try? JSONDecoder().decode(CachedMonetizationFlags.self, from: data)
    }

    static func save(_ flags: CachedMonetizationFlags, userID: String, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(flags) else { return }
        defaults.set(data, forKey: cacheKey(userID: userID))
    }

    private func notifyChange() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .monetizationConfigurationDidChange, object: nil)
        }
    }
}

protocol MonetizationConfigurationRefreshing: Sendable {
    func refreshMonetizationConfiguration(for profileID: ProfileID) async
}
