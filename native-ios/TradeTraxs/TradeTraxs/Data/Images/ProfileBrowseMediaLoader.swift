import UIKit

/// Shared Profile list/grid media fetch — memory cache first, then pipeline tiers, then network.
nonisolated enum ProfileBrowseMediaLoader {
    static func gridPixelBudget(displayScale: CGFloat) -> Int {
        max(256, Int(180 * displayScale))
    }

    /// Matches ``ProfileCompactThumbnailLayout`` width (96pt) × 2× scale.
    static func listPixelBudget(displayScale: CGFloat) -> Int {
        max(128, Int(96 * displayScale * 2))
    }

    static func makeRequest(
        reference: MediaReference,
        purpose: ImagePurpose,
        maxPixelSize: Int
    ) -> ImageRequest {
        ImageRequest(
            reference: reference,
            purpose: purpose,
            maxPixelSize: maxPixelSize,
            allowsProgressiveLoading: true,
            deliveryQuality: .profileGrid
        )
    }

    static func loadUIImage(
        reference: MediaReference,
        purpose: ImagePurpose,
        maxPixelSize: Int,
        displayScale: CGFloat,
        imagePipeline: any ImagePipeline,
        existing: UIImage?
    ) async -> UIImage? {
        if let existing { return existing }
        if let cached = ProfileBrowseMediaDisplayCache.uiImage(reference: reference, purpose: purpose) {
            return cached
        }

        let request = makeRequest(
            reference: reference,
            purpose: purpose,
            maxPixelSize: maxPixelSize
        )

        if let cached = await imagePipeline.bestCachedImageDataWithTier(for: request),
           let decoded = decode(data: cached.data, displayScale: displayScale)
        {
            ProfileBrowseMediaDisplayCache.store(decoded, reference: reference, purpose: purpose)
            return decoded
        }

        do {
            let data = try await imagePipeline.data(for: request)
            return decode(data: data, displayScale: displayScale).map { image in
                ProfileBrowseMediaDisplayCache.store(image, reference: reference, purpose: purpose)
                return image
            }
        } catch {
            return nil
        }
    }

    private static func decode(data: Data, displayScale: CGFloat) -> UIImage? {
        let decoded = UIImage(data: data, scale: displayScale)
        return decoded.map { MediaImageOrientation.normalized($0) }
    }
}
