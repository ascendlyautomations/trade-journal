import Foundation

nonisolated struct UploadRequest: Sendable {
    var bucket: String
    var path: String
    var data: Data
    var contentType: String
    var purpose: ImagePurpose?
}

nonisolated protocol UploadService: Sendable {
    func upload(_ request: UploadRequest) async throws -> MediaReference
}

nonisolated struct DefaultUploadService: UploadService {
    private let storage: any ObjectStorageProviding

    init(storage: any ObjectStorageProviding) {
        self.storage = storage
    }

    func upload(_ request: UploadRequest) async throws -> MediaReference {
        let path = try await storage.upload(
            bucket: request.bucket,
            path: request.path,
            data: request.data,
            contentType: request.contentType
        )
        let kind: MediaKind = request.contentType.hasPrefix("video") ? .video
            : request.contentType.hasPrefix("image") ? .image
            : .file
        return MediaReference(id: path, kind: kind, altText: nil)
    }
}
