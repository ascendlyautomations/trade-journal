import Foundation

/// Last-known broker import eligibility for fast Dashboard / routing UI (presentation only).
nonisolated enum BrokerImportEligibilityDiskCache {
    private static let folderName = "BrokerImportEligibility"
    static let presentationSoftStaleSeconds: TimeInterval = 30 * 60
    private static let softStaleSeconds = presentationSoftStaleSeconds

    struct Blob: Codable, Sendable {
        var viewerID: String
        var savedAt: Date
        var response: BrokerImportEligibilityResponse
    }

    static func save(_ response: BrokerImportEligibilityResponse, viewerID: String) {
        let blob = Blob(viewerID: viewerID, savedAt: Date(), response: response)
        write(blob, file: fileName(viewerID: viewerID))
    }

    static func load(viewerID: String) -> Blob? {
        guard let blob: Blob = read(file: fileName(viewerID: viewerID)) else { return nil }
        guard blob.viewerID == viewerID else { return nil }
        return blob
    }

    static func isStale(_ blob: Blob, now: Date = Date()) -> Bool {
        now.timeIntervalSince(blob.savedAt) > softStaleSeconds
    }

    static func clear(viewerID: String) {
        remove(file: fileName(viewerID: viewerID))
    }

    private static func fileName(viewerID: String) -> String {
        "broker-eligibility-\(viewerID).json"
    }

    private static func directoryURL() -> URL? {
        PersistentAppDataDiskCache.directoryURL(component: folderName)
    }

    private static func write<T: Encodable>(_ value: T, file: String) {
        guard let dir = directoryURL() else { return }
        let url = dir.appendingPathComponent(file)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private static func read<T: Decodable>(file: String) -> T? {
        guard let dir = directoryURL() else { return nil }
        let url = dir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func remove(file: String) {
        guard let dir = directoryURL() else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
    }
}
