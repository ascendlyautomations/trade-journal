import Foundation

nonisolated struct DownloadRequest: Sendable {
    var bucket: String
    var path: String
}

nonisolated protocol DownloadService: Sendable {
    func download(_ request: DownloadRequest) async throws -> Data
}

nonisolated struct DefaultDownloadService: DownloadService {
    private let storage: any ObjectStorageProviding

    init(storage: any ObjectStorageProviding) {
        self.storage = storage
    }

    func download(_ request: DownloadRequest) async throws -> Data {
        try await storage.download(bucket: request.bucket, path: request.path)
    }
}
