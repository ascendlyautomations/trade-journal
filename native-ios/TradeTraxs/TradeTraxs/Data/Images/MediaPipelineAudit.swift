import Foundation
import ImageIO
import UIKit

#if DEBUG
/// End-to-end image pipeline trace — correlate Feed vs Detail loads for the same storage reference.
nonisolated enum MediaPipelineAudit {
    struct FetchReport: Sendable {
        var surface: String
        var mediaID: String
        var storageReference: String
        var purpose: String
        var deliveryQuality: String
        var cacheKey: String
        var cacheHit: Bool
        var objectURL: String?
        var fetchURL: String
        var transformPreset: String?
        var transformParams: String?
        var byteCount: Int
        var encodedPixelWidth: Int?
        var encodedPixelHeight: Int?
    }

    struct DecodeReport: Sendable {
        var surface: String
        var mediaID: String
        var storageReference: String
        var deliveryQuality: String
        var cacheKey: String
        var source: String
        var preNormalizeOrientation: String
        var preNormalizePixelWidth: Int
        var preNormalizePixelHeight: Int
        var preNormalizeSize: String
        var preNormalizeScale: CGFloat
        var postNormalizePixelWidth: Int
        var postNormalizePixelHeight: Int
        var postNormalizeSize: String
        var postNormalizeScale: CGFloat
        var postNormalizeOrientation: String
    }

    struct RenderReport: Sendable {
        var surface: String
        var mediaID: String
        var storageReference: String
        var deliveryQuality: String
        var decodedPixelWidth: Int
        var decodedPixelHeight: Int
        var containerBounds: String
        var imageViewBounds: String
        var imageViewFrame: String
        var contentMode: String
    }

    static func logFetch(_ report: FetchReport) {
        let encoded = encodedDimensionsLabel(
            width: report.encodedPixelWidth,
            height: report.encodedPixelHeight
        )
        print(
            """
            [MEDIA_PIPELINE_AUDIT] phase=fetch surface=\(report.surface) \
            mediaID=\(report.mediaID) storageReference=\(report.storageReference) \
            purpose=\(report.purpose) deliveryQuality=\(report.deliveryQuality) \
            cacheKey=\(report.cacheKey) cacheHit=\(report.cacheHit) \
            objectURL=\(report.objectURL ?? "nil") \
            fetchURL=\(report.fetchURL) \
            transformPreset=\(report.transformPreset ?? "none") \
            transformParams=\(report.transformParams ?? "none") \
            bytes=\(report.byteCount) encodedPixels=\(encoded)
            """
        )
    }

    static func logDecode(_ report: DecodeReport) {
        print(
            """
            [MEDIA_PIPELINE_AUDIT] phase=decode surface=\(report.surface) \
            mediaID=\(report.mediaID) storageReference=\(report.storageReference) \
            deliveryQuality=\(report.deliveryQuality) cacheKey=\(report.cacheKey) source=\(report.source) \
            preNormalize orientation=\(report.preNormalizeOrientation) \
            pixels=\(report.preNormalizePixelWidth)x\(report.preNormalizePixelHeight) \
            size=\(report.preNormalizeSize) scale=\(formatScale(report.preNormalizeScale)) \
            postNormalize orientation=\(report.postNormalizeOrientation) \
            pixels=\(report.postNormalizePixelWidth)x\(report.postNormalizePixelHeight) \
            size=\(report.postNormalizeSize) scale=\(formatScale(report.postNormalizeScale))
            """
        )
    }

    static func logRender(_ report: RenderReport) {
        print(
            """
            [MEDIA_PIPELINE_AUDIT] phase=render surface=\(report.surface) \
            mediaID=\(report.mediaID) storageReference=\(report.storageReference) \
            deliveryQuality=\(report.deliveryQuality) \
            decodedPixels=\(report.decodedPixelWidth)x\(report.decodedPixelHeight) \
            containerBounds=\(report.containerBounds) \
            imageViewBounds=\(report.imageViewBounds) \
            imageViewFrame=\(report.imageViewFrame) contentMode=\(report.contentMode)
            """
        )
    }

    static func encodedPixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        guard let width, let height, width > 0, height > 0 else { return nil }
        return (width, height)
    }

    static func describePreset(_ preset: StorageImageTransform.Preset) -> (name: String, params: String) {
        switch preset {
        case .avatar:
            return ("avatar", "width=96 height=96 quality=80 resize=cover")
        case .feedThumb:
            return ("feedThumb", "width=640 quality=75 resize=default")
        case .feedDetail:
            return ("feedDetail", "width=1280 quality=82 resize=default")
        case .story:
            return ("story", "width=1080 quality=80 resize=contain")
        case .reelThumb:
            return ("reelThumb", "width=560 height=996 quality=75 resize=cover")
        }
    }

    static func cacheKey(
        referenceID: String,
        purpose: ImagePurpose,
        deliveryQuality: ImageDeliveryQuality,
        maxPixelSize: Int?
    ) -> String {
        "\(referenceID)|\(purpose.rawValue)|\(deliveryQuality.rawValue)|\(maxPixelSize ?? 0)"
    }

    static func orientationLabel(_ orientation: UIImage.Orientation) -> String {
        switch orientation {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        case .upMirrored: return "upMirrored"
        case .downMirrored: return "downMirrored"
        case .leftMirrored: return "leftMirrored"
        case .rightMirrored: return "rightMirrored"
        @unknown default: return "unknown"
        }
    }

    static func uiImagePointSizeLabel(_ image: UIImage) -> String {
        String(format: "%.1fx%.1f", image.size.width, image.size.height)
    }

    static func cgPixelSize(of image: UIImage) -> (width: Int, height: Int) {
        if let cg = image.cgImage {
            return (cg.width, cg.height)
        }
        return (
            Int((image.size.width * image.scale).rounded()),
            Int((image.size.height * image.scale).rounded())
        )
    }

    static func describeRect(_ rect: CGRect) -> String {
        String(
            format: "(%.1f,%.1f,%.1fx%.1f)",
            rect.origin.x, rect.origin.y, rect.width, rect.height
        )
    }

    private static func encodedDimensionsLabel(width: Int?, height: Int?) -> String {
        guard let width, let height else { return "unknown" }
        return "\(width)x\(height)"
    }

    private static func formatScale(_ scale: CGFloat) -> String {
        String(format: "%.2f", scale)
    }
}
#else
nonisolated enum MediaPipelineAudit {
    struct FetchReport: Sendable {
        var surface: String = ""
        var mediaID: String = ""
        var storageReference: String = ""
        var purpose: String = ""
        var deliveryQuality: String = ""
        var cacheKey: String = ""
        var cacheHit: Bool = false
        var objectURL: String?
        var fetchURL: String = ""
        var transformPreset: String?
        var transformParams: String?
        var byteCount: Int = 0
        var encodedPixelWidth: Int?
        var encodedPixelHeight: Int?
    }
    struct DecodeReport: Sendable {
        var surface: String = ""
        var mediaID: String = ""
        var storageReference: String = ""
        var deliveryQuality: String = ""
        var cacheKey: String = ""
        var source: String = ""
        var preNormalizeOrientation: String = ""
        var preNormalizePixelWidth: Int = 0
        var preNormalizePixelHeight: Int = 0
        var preNormalizeSize: String = ""
        var preNormalizeScale: CGFloat = 1
        var postNormalizePixelWidth: Int = 0
        var postNormalizePixelHeight: Int = 0
        var postNormalizeSize: String = ""
        var postNormalizeScale: CGFloat = 1
        var postNormalizeOrientation: String = ""
    }
    struct RenderReport: Sendable {
        var surface: String = ""
        var mediaID: String = ""
        var storageReference: String = ""
        var deliveryQuality: String = ""
        var decodedPixelWidth: Int = 0
        var decodedPixelHeight: Int = 0
        var containerBounds: String = ""
        var imageViewBounds: String = ""
        var imageViewFrame: String = ""
        var contentMode: String = ""
    }

    static func logFetch(_ report: FetchReport) {}
    static func logDecode(_ report: DecodeReport) {}
    static func logRender(_ report: RenderReport) {}
    static func encodedPixelSize(of data: Data) -> (width: Int, height: Int)? { nil }
    static func cacheKey(
        referenceID: String,
        purpose: ImagePurpose,
        deliveryQuality: ImageDeliveryQuality,
        maxPixelSize: Int?
    ) -> String { "" }
}
#endif
