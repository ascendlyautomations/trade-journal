import Foundation
import Observation

/// User-scoped custom instrument symbols — survives logout/login and app restart.
///
/// Web has no instrument table; explicit picker customs complement `trades.ticker` history.
/// Intentionally **not** cleared in ``SessionScopedCaches`` — keyed per profile ID.
@Observable
@MainActor
final class UserCustomInstrumentStore {
    static let shared = UserCustomInstrumentStore()

    private let defaults: UserDefaults
    private var cache: [ProfileID: [String]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func customSymbols(for profileID: ProfileID) -> [String] {
        if let cached = cache[profileID] {
            return cached
        }
        let loaded = load(profileID)
        cache[profileID] = loaded
        return loaded
    }

    @discardableResult
    func add(_ rawSymbol: String, for profileID: ProfileID) -> String? {
        let normalized = Self.normalize(rawSymbol)
        guard !normalized.isEmpty else { return nil }

        var list = customSymbols(for: profileID)
        if let existingIndex = list.firstIndex(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            let existing = list.remove(at: existingIndex)
            list.insert(existing, at: 0)
            save(list, for: profileID)
            return existing
        }

        list.insert(normalized, at: 0)
        save(list, for: profileID)
        return normalized
    }

    func remove(_ rawSymbol: String, for profileID: ProfileID) {
        let normalized = Self.normalize(rawSymbol)
        guard !normalized.isEmpty else { return }
        var list = customSymbols(for: profileID)
        list.removeAll { $0.caseInsensitiveCompare(normalized) == .orderedSame }
        save(list, for: profileID)
    }

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func save(_ symbols: [String], for profileID: ProfileID) {
        cache[profileID] = symbols
        defaults.set(symbols, forKey: storageKey(for: profileID))
    }

    private func load(_ profileID: ProfileID) -> [String] {
        defaults.stringArray(forKey: storageKey(for: profileID)) ?? []
    }

    private func storageKey(for profileID: ProfileID) -> String {
        "tt.customInstruments.v1.\(profileID.rawValue)"
    }
}
