import Foundation

/// Object-storage abstraction over Supabase Storage.
nonisolated protocol ObjectStorageProviding: Sendable {
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String
    func download(bucket: String, path: String) async throws -> Data
    func delete(bucket: String, path: String) async throws
    func publicURL(bucket: String, path: String) -> URL?
}

/// Well-known buckets used by TradeTraxs media.
nonisolated enum StorageBucket: String, Sendable {
    case screenshots
    case avatars
    case stories
    case reels
    case rooms = "room-images"
    case posts = "post-media"
}

nonisolated struct SupabaseObjectStorageProvider: ObjectStorageProviding {
    private let storage: any SupabaseStorageProviding

    init(storage: any SupabaseStorageProviding) {
        self.storage = storage
    }

    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        try await storage.upload(bucket: bucket, path: path, data: data, contentType: contentType)
    }

    func download(bucket: String, path: String) async throws -> Data {
        try await storage.download(bucket: bucket, path: path)
    }

    func delete(bucket: String, path: String) async throws {
        try await storage.delete(bucket: bucket, path: path)
    }

    func publicURL(bucket: String, path: String) -> URL? {
        storage.publicURL(bucket: bucket, path: path)
    }
}
