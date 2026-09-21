import Foundation

/// Production image cache keys — shared by pipeline, audit, and Feed warm/prefetch.
nonisolated enum ImageCacheKey {
    nonisolated static func make(for request: ImageRequest) -> String {
        make(
            referenceID: request.reference.id,
            purpose: request.purpose,
            deliveryQuality: request.deliveryQuality,
            maxPixelSize: request.maxPixelSize
        )
    }

    nonisolated static func make(
        referenceID: String,
        purpose: ImagePurpose,
        deliveryQuality: ImageDeliveryQuality,
        maxPixelSize: Int?
    ) -> String {
        let transformRevision: String = {
            switch deliveryQuality {
            case .feedDisplay:
                return "|feedRev=\(StorageImageTransform.feedDisplayCacheRevision)"
            case .profileGrid:
                return "|profileGridRev=\(StorageImageTransform.profileGridCacheRevision)"
            default:
                return ""
            }
        }()
        return "\(referenceID)|\(purpose.rawValue)|\(deliveryQuality.rawValue)|\(maxPixelSize ?? 0)\(transformRevision)"
    }
}
