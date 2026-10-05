import Foundation

/// Memory + disk cache for the published Demo snapshot.
///
/// Empty memory means callers keep using the bundled Phase 1 generators.
nonisolated final class DemoSnapshotStore: @unchecked Sendable {
    static let shared = DemoSnapshotStore()

    private let lock = NSLock()
    private var memory: DemoSnapshot?
    private var suppressSnapshot = false
    private let cacheFileURL: URL

    init(cacheFileURL: URL? = nil) {
        if let cacheFileURL {
            self.cacheFileURL = cacheFileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.cacheFileURL = base.appendingPathComponent("TradeTraxs/demo-snapshot.json")
        }
    }

    var current: DemoSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        if suppressSnapshot { return nil }
        return memory
    }

    func withBundledSource<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        let previous = suppressSnapshot
        suppressSnapshot = true
        lock.unlock()
        defer {
            lock.lock()
            suppressSnapshot = previous
            lock.unlock()
        }
        return try body()
    }

    func install(_ snapshot: DemoSnapshot) {
        guard snapshot.validate().isEmpty else { return }
        lock.lock()
        memory = snapshot
        lock.unlock()
    }

    func clearMemory() {
        lock.lock()
        memory = nil
        lock.unlock()
    }

    @discardableResult
    func activateCachedSnapshot() -> DemoSnapshot? {
        guard let data = try? Data(contentsOf: cacheFileURL) else { return current }
        guard let snapshot = try? DemoSnapshotCoding.decode(data), snapshot.validate().isEmpty else {
            try? FileManager.default.removeItem(at: cacheFileURL)
            return current
        }
        install(snapshot)
        return snapshot
    }

    func persist(_ snapshot: DemoSnapshot) throws {
        let directory = cacheFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try DemoSnapshotCoding.encode(snapshot)
        try data.write(to: cacheFileURL, options: .atomic)
    }

    /// Decode a remote payload. A bad document leaves the installed snapshot in place.
    func ingestRemoteData(_ data: Data) -> DemoSnapshotRefreshResult {
        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == Data("null".utf8) {
            return .unavailable
        }
        guard let snapshot = try? DemoSnapshotCoding.decode(trimmed), snapshot.validate().isEmpty else {
            return .rejected
        }
        if let current, snapshot.version <= current.version {
            return .unchanged(version: current.version)
        }
        install(snapshot)
        do {
            try persist(snapshot)
        } catch {
            return .applied(version: snapshot.version)
        }
        return .applied(version: snapshot.version)
    }

    /// Fetches the published snapshot and installs it when the version is newer and valid.
    /// Entry does not await this. The fetch is not cancelled after a short timeout, so a
    /// slower response still replaces the cache.
    func refresh(
        timeoutNanoseconds: UInt64 = 1_500_000_000,
        fetcher: @escaping @Sendable () async throws -> Data
    ) async -> DemoSnapshotRefreshResult {
        _ = timeoutNanoseconds
        let cached = current?.version
        do {
            let data = try await fetcher()
            let result = ingestRemoteData(data)
            DemoSnapshotLog.remote(result, cached: cached, selected: current?.version)
            return result
        } catch {
            DemoSnapshotLog.event("cached=\(cached.map(String.init) ?? "none") server=unavailable selected=\(cached.map(String.init) ?? "none") source=\(cached == nil ? "bundled" : "memory") result=unavailable")
            return .unavailable
        }
    }
}

nonisolated enum DemoSnapshotLog {
    static func event(_ message: String) {
        #if DEBUG
        print("[DemoSnapshot] \(message)")
        #endif
    }

    static func remote(_ result: DemoSnapshotRefreshResult, cached: Int?, selected: Int?) {
        switch result {
        case .applied(let version):
            event("cached=\(cached.map(String.init) ?? "none") server=\(version) selected=\(version) source=remote result=applied")
        case .unchanged(let version):
            event("cached=\(cached.map(String.init) ?? "none") server=\(version) selected=\(selected.map(String.init) ?? "none") source=memory result=unchanged")
        case .rejected:
            event("cached=\(cached.map(String.init) ?? "none") server=rejected selected=\(selected.map(String.init) ?? "none") source=\(cached == nil ? "bundled" : "memory") result=rejected")
        case .unavailable:
            event("cached=\(cached.map(String.init) ?? "none") server=unavailable selected=\(selected.map(String.init) ?? "none") source=\(cached == nil ? "bundled" : "memory") result=unavailable")
        }
    }
}

private nonisolated extension Data {
    func trimmingCharacters(in set: CharacterSet) -> Data {
        var bytes = self
        while let first = bytes.first, set.contains(UnicodeScalar(first)) {
            bytes.removeFirst()
        }
        while let last = bytes.last, set.contains(UnicodeScalar(last)) {
            bytes.removeLast()
        }
        return bytes
    }
}
