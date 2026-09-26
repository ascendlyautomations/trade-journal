import Foundation

/// User-scoped dismissed tour versions.
///
/// Key: `tt.contextualTour.dismissed:{userID}`
/// Value: JSON object of tour id → highest dismissed version, e.g. `{"dashboard":1}`.
/// Logout must not delete this key.
struct ContextualTourProgressStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func storageKey(userID: String) -> String {
        "tt.contextualTour.dismissed:\(userID)"
    }

    func dismissedVersion(for tour: ContextualTourID, userID: String) -> Int {
        records(for: userID)[tour.rawValue] ?? 0
    }

    func dismissedVersion(forTourKey tourKey: String, userID: String) -> Int {
        records(for: userID)[tourKey] ?? 0
    }

    /// Writes the highest version. A lower version never replaces a higher one.
    func dismiss(_ tour: ContextualTourID, version: Int, userID: String) {
        setRecord(version, tourKey: tour.rawValue, userID: userID)
    }

    func setRecord(_ version: Int, tourKey: String, userID: String) {
        var map = records(for: userID)
        let current = map[tourKey] ?? 0
        map[tourKey] = max(current, version)
        persist(map, userID: userID)
    }

    func clearDismissals(userID: String) {
        defaults.removeObject(forKey: Self.storageKey(userID: userID))
    }

    func records(for userID: String) -> [String: Int] {
        guard let data = defaults.data(forKey: Self.storageKey(userID: userID)) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private func persist(_ map: [String: Int], userID: String) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: Self.storageKey(userID: userID))
    }
}
