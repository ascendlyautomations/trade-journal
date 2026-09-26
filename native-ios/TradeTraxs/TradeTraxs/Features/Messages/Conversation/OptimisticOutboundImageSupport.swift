import UIKit

/// Stable media IDs + in-memory bytes for outbound image messages (DM + Trade Room).
nonisolated enum OptimisticOutboundImageSupport {
    static let mediaIDPrefix = "optimistic-outbound-image:"

    static func isOptimisticMediaID(_ id: String) -> Bool {
        id.hasPrefix(mediaIDPrefix)
    }

    static func mediaReference(for messageID: MessageID) -> MediaReference {
        let id = "\(mediaIDPrefix)\(messageID.rawValue)"
        return MediaReference(id: id, kind: .image, altText: nil)
    }

    static func messageID(fromOptimisticMediaID id: String) -> MessageID? {
        guard isOptimisticMediaID(id) else { return nil }
        let raw = String(id.dropFirst(mediaIDPrefix.count))
        guard !raw.isEmpty else { return nil }
        return MessageID(raw)
    }
}

@MainActor
final class OptimisticOutboundImageStore {
    static let shared = OptimisticOutboundImageStore()

    private var images: [MessageID: UIImage] = [:]
    private var jpegData: [MessageID: Data] = [:]

    private init() {}

    func register(messageID: MessageID, jpegData data: Data) {
        jpegData[messageID] = data
        if let image = UIImage(data: data) {
            images[messageID] = image
        }
    }

    func uiImage(for referenceID: String) -> UIImage? {
        guard let messageID = OptimisticOutboundImageSupport.messageID(fromOptimisticMediaID: referenceID) else {
            return nil
        }
        return images[messageID]
    }

    func jpegData(for messageID: MessageID) -> Data? {
        jpegData[messageID]
    }

    func remove(messageID: MessageID) {
        images.removeValue(forKey: messageID)
        jpegData.removeValue(forKey: messageID)
    }
}

enum OptimisticOutboundImageSendSupport {
    static func prepareOptimisticAttachments(
        tempID: MessageID,
        localImageData: Data
    ) -> [MessageAttachment] {
        OptimisticOutboundImageStore.shared.register(messageID: tempID, jpegData: localImageData)
        let media = OptimisticOutboundImageSupport.mediaReference(for: tempID)
        return [
            MessageAttachment(
                id: media.id,
                media: media,
                tradeID: nil
            ),
        ]
    }

    static func uploadJPEG(
        localImageData: Data,
        storagePath: String,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding
    ) async throws -> String {
        let reference = try await uploadService.upload(
            UploadRequest(
                bucket: StorageBucket.screenshots.rawValue,
                path: storagePath,
                data: localImageData,
                contentType: "image/jpeg",
                purpose: .tradeScreenshot
            )
        )
        if let publicURL = objectStorage.publicURL(
            bucket: StorageBucket.screenshots.rawValue,
            path: reference.id
        ) {
            return publicURL.absoluteString
        }
        return reference.id
    }

    static func imageAttachments(for url: String) -> [MessageAttachment] {
        [
            MessageAttachment(
                id: url,
                media: MediaReference(id: url, kind: .image, altText: nil),
                tradeID: nil
            ),
        ]
    }
}
