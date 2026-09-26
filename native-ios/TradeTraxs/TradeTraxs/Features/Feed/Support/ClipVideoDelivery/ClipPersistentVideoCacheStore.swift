import Foundation

/// On-disk immutable reel MP4 cache with LRU metadata (Application Support).
actor ClipPersistentVideoCacheStore {
    struct Entry: Codable, Equatable, Sendable {
        var cacheKey: String
        var urlIdentity: String
        var fileName: String
        var byteCount: Int64
        var lastAccessUnix: TimeInterval
    }

    struct Index: Codable, Equatable, Sendable {
        var schemaVersion: Int = 1
        var entries: [String: Entry] = [:]
    }

    static let defaultMaxDiskBytes: Int64 = 300 * 1_024 * 1_024

    private let maxDiskBytes: Int64
    private let fileManager: FileManager
    private let rootDirectory: URL
    private let indexURL: URL
    private var index: Index

    init(
        maxDiskBytes: Int64? = nil,
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil
    ) throws {
        self.maxDiskBytes = maxDiskBytes ?? ClipPersistentVideoCacheStore.defaultMaxDiskBytes
        self.fileManager = fileManager
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else if let dir = PersistentAppDataDiskCache.directoryURL(component: "ClipVideoCache") {
            self.rootDirectory = dir
        } else {
            throw ClipVideoCacheError.unavailableDirectory
        }
        self.indexURL = self.rootDirectory.appendingPathComponent("index.json")
        try fileManager.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
        let loaded = Self.loadIndex(from: self.indexURL)
        let reconciled = Self.reconcile(
            index: loaded,
            rootDirectory: self.rootDirectory,
            fileManager: fileManager
        )
        self.index = reconciled.index
        if reconciled.changed {
            Self.persist(reconciled.index, to: self.indexURL)
        }
    }

    func readyFileURL(for cacheKey: String) -> URL? {
        guard var entry = index.entries[cacheKey] else { return nil }
        let fileURL = rootDirectory.appendingPathComponent(entry.fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            index.entries.removeValue(forKey: cacheKey)
            persistIndexAsync()
            return nil
        }
        guard ClipMP4FileValidator.isLikelyCompleteMP4(at: fileURL) else {
            removeEntryAndFile(cacheKey: cacheKey, entry: entry)
            return nil
        }
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard size > 0, size == entry.byteCount else {
            removeEntryAndFile(cacheKey: cacheKey, entry: entry)
            return nil
        }
        entry.lastAccessUnix = Date().timeIntervalSince1970
        index.entries[cacheKey] = entry
        persistIndexAsync()
        return fileURL
    }

    func touch(cacheKey: String) {
        guard var entry = index.entries[cacheKey] else { return }
        entry.lastAccessUnix = Date().timeIntervalSince1970
        index.entries[cacheKey] = entry
        persistIndexAsync()
    }

    func completeDownload(
        cacheKey: String,
        urlIdentity: String,
        stagedFileURL: URL
    ) throws -> Int64 {
        guard ClipMP4FileValidator.isLikelyCompleteMP4(at: stagedFileURL) else {
            try? fileManager.removeItem(at: stagedFileURL)
            throw ClipVideoCacheError.invalidCompleteFile
        }
        let byteCount = Int64((try stagedFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard byteCount > 0 else {
            try? fileManager.removeItem(at: stagedFileURL)
            throw ClipVideoCacheError.invalidCompleteFile
        }

        let fileName = "\(cacheKey).mp4"
        let destination = rootDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: stagedFileURL, to: destination)

        let now = Date().timeIntervalSince1970
        index.entries[cacheKey] = Entry(
            cacheKey: cacheKey,
            urlIdentity: urlIdentity,
            fileName: fileName,
            byteCount: byteCount,
            lastAccessUnix: now
        )
        persistIndexAsync()
        evictIfNeeded()
        return byteCount
    }

    func partFileURL(for cacheKey: String) -> URL {
        rootDirectory.appendingPathComponent("\(cacheKey).part")
    }

    func fileURL(for cacheKey: String) -> URL {
        rootDirectory.appendingPathComponent("\(cacheKey).mp4")
    }

    func invalidate(cacheKey: String) {
        guard let entry = index.entries[cacheKey] else { return }
        removeEntryAndFile(cacheKey: cacheKey, entry: entry)
    }

    func totalBytesOnDisk() -> Int64 {
        index.entries.values.reduce(0) { $0 + $1.byteCount }
    }

    func entryCount() -> Int {
        index.entries.count
    }

    /// Removes all cached reel MP4s, `.part` files, and resets `index.json` (Clip cache only).
    func clearAllContents() {
        let urls = (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in urls {
            try? fileManager.removeItem(at: url)
        }
        index = Index()
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: indexURL, options: [.atomic])
        }
        ClipVideoDeliveryTrace.cache("clearAllContents removedFiles=\(urls.count)")
    }

    func evictIfNeeded() {
        var total = totalBytesOnDisk()
        guard total > maxDiskBytes else { return }

        let sorted = index.entries.values.sorted { $0.lastAccessUnix < $1.lastAccessUnix }
        for entry in sorted where total > maxDiskBytes {
            let fileURL = rootDirectory.appendingPathComponent(entry.fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
            index.entries.removeValue(forKey: entry.cacheKey)
            total -= entry.byteCount
            ClipVideoDeliveryTrace.cache("evicted key=\(entry.cacheKey.prefix(8)) bytes=\(entry.byteCount)")
        }
        persistIndexAsync()
    }

    // MARK: - Private

    private func persistIndexAsync() {
        Self.persist(index, to: indexURL)
    }

    private nonisolated static func loadIndex(from indexURL: URL) -> Index {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode(Index.self, from: data)
        else { return Index() }
        return decoded
    }

    private nonisolated static func persist(_ index: Index, to indexURL: URL) {
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(index) else { return }
            try? data.write(to: indexURL, options: [.atomic])
        }
    }

    private nonisolated static func reconcile(
        index: Index,
        rootDirectory: URL,
        fileManager: FileManager
    ) -> (index: Index, changed: Bool) {
        var next = index
        var changed = false
        for (key, entry) in index.entries {
            let fileURL = rootDirectory.appendingPathComponent(entry.fileName)
            if !fileManager.fileExists(atPath: fileURL.path)
                || !ClipMP4FileValidator.isLikelyCompleteMP4(at: fileURL)
            {
                next.entries.removeValue(forKey: key)
                changed = true
            }
        }
        let partFiles = (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in partFiles where url.pathExtension == "part" {
            try? fileManager.removeItem(at: url)
        }
        return (next, changed)
    }

    private func removeEntryAndFile(cacheKey: String, entry: Entry) {
        index.entries.removeValue(forKey: cacheKey)
        let fileURL = rootDirectory.appendingPathComponent(entry.fileName)
        try? fileManager.removeItem(at: fileURL)
        persistIndexAsync()
    }
}

enum ClipVideoCacheError: Error, Equatable {
    case unavailableDirectory
    case invalidCompleteFile
    case downloadFailed
    case diskFull
}

nonisolated enum ClipMP4FileValidator {
    nonisolated static func isLikelyCompleteMP4(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 12), header.count >= 8 else { return false }
        let box = String(data: header.subdata(in: 4 ..< 8), encoding: .ascii)
        return box == "ftyp" || box == "moov"
    }
}
