import CryptoKit
import Foundation

/// Bounded on-disk image byte cache for **public** HTTP-fetched media only.
nonisolated final class DiskImageCache: ImageCaching, @unchecked Sendable {
    struct Policy: Sendable {
        var maxTotalBytes: Int = 120 * 1_024 * 1_024
        var maxEntryAge: TimeInterval = 14 * 24 * 60 * 60
    }

    private struct IndexEntry: Codable, Sendable {
        var key: String
        var fileName: String
        var byteCount: Int
        var createdAt: Date
        var lastAccess: Date
    }

    private struct IndexFile: Codable {
        var entries: [IndexEntry]
    }

    private let policy: Policy
    private let rootURL: URL
    private let ioQueue = DispatchQueue(label: "com.tradetrxs.disk-image-cache", qos: .utility)
    private let indexLock = NSLock()
    private var index: [String: IndexEntry] = [:]

    init(policy: Policy = Policy()) {
        self.policy = policy
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        rootURL = base.appendingPathComponent("MediaImageCache/public", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        loadIndex()
    }

    func imageData(forKey key: String) async -> Data? {
        await withCheckedContinuation { continuation in
            ioQueue.async { [weak self] in
                continuation.resume(returning: self?.readLocked(key: key))
            }
        }
    }

    func setImageData(_ data: Data, forKey key: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ioQueue.async { [weak self] in
                self?.writeLocked(data: data, key: key)
                continuation.resume()
            }
        }
    }

    func removeImage(forKey key: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ioQueue.async { [weak self] in
                self?.removeLocked(key: key)
                continuation.resume()
            }
        }
    }

    func removeAllImages() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ioQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                indexLock.lock()
                index.removeAll()
                indexLock.unlock()
                try? FileManager.default.removeItem(at: rootURL)
                try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
                continuation.resume()
            }
        }
    }

    // MARK: - Private

    private func loadIndex() {
        let indexURL = rootURL.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode(IndexFile.self, from: data)
        else { return }
        indexLock.lock()
        index = Dictionary(uniqueKeysWithValues: decoded.entries.map { ($0.key, $0) })
        indexLock.unlock()
        ioQueue.async { [weak self] in
            self?.evictIfNeededLocked(force: false)
        }
    }

    private func persistIndexLocked() {
        let indexURL = rootURL.appendingPathComponent("index.json")
        let payload = IndexFile(entries: Array(index.values))
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let temp = rootURL.appendingPathComponent("index.\(UUID().uuidString).tmp")
        do {
            try data.write(to: temp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(indexURL, withItemAt: temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
        }
    }

    private func fileName(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".img"
    }

    private func readLocked(key: String) -> Data? {
        indexLock.lock()
        guard var entry = index[key] else {
            indexLock.unlock()
            return nil
        }
        if Date().timeIntervalSince(entry.createdAt) > policy.maxEntryAge {
            removeLocked(key: key)
            indexLock.unlock()
            return nil
        }
        entry.lastAccess = Date()
        index[key] = entry
        persistIndexLocked()
        indexLock.unlock()

        let fileURL = rootURL.appendingPathComponent(entry.fileName)
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            removeLocked(key: key)
            return nil
        }
        return data
    }

    private func writeLocked(data: Data, key: String) {
        guard !data.isEmpty else { return }
        let name = fileName(for: key)
        let fileURL = rootURL.appendingPathComponent(name)
        let tempURL = rootURL.appendingPathComponent("\(name).\(UUID().uuidString).tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        indexLock.lock()
        if let existing = index[key] {
            try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(existing.fileName))
        }
        let now = Date()
        index[key] = IndexEntry(
            key: key,
            fileName: name,
            byteCount: data.count,
            createdAt: now,
            lastAccess: now
        )
        persistIndexLocked()
        indexLock.unlock()
        evictIfNeededLocked(force: false)
    }

    private func removeLocked(key: String) {
        indexLock.lock()
        guard let entry = index.removeValue(forKey: key) else {
            indexLock.unlock()
            return
        }
        persistIndexLocked()
        indexLock.unlock()
        try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(entry.fileName))
    }

    private func evictIfNeededLocked(force: Bool) {
        indexLock.lock()
        let now = Date()
        var entries = Array(index.values)
        entries.removeAll { now.timeIntervalSince($0.createdAt) > policy.maxEntryAge }
        for stale in entries where index[stale.key] != nil {
            index.removeValue(forKey: stale.key)
            try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(stale.fileName))
        }

        var total = index.values.reduce(0) { $0 + $1.byteCount }
        if force || total > policy.maxTotalBytes {
            let sorted = index.values.sorted { $0.lastAccess < $1.lastAccess }
            for entry in sorted where total > policy.maxTotalBytes || force {
                guard index.removeValue(forKey: entry.key) != nil else { continue }
                total -= entry.byteCount
                try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(entry.fileName))
            }
        }
        persistIndexLocked()
        indexLock.unlock()
    }
}
