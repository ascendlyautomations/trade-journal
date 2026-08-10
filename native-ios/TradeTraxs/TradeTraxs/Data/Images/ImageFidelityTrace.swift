import CoreGraphics
import Foundation
import ImageIO
import OSLog
import UIKit

/// End-to-end image fidelity probe — logs pixel dimensions at each pipeline stage.
///
/// Enable with launch argument `-uitesting-feed-image-diagnostics` or DEBUG builds
/// when `ImageFidelityTrace.isEnabled` is true.
nonisolated enum ImageFidelityTrace {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uitesting-feed-image-diagnostics")
            || ProcessInfo.processInfo.environment["FEED_IMAGE_DIAGNOSTICS"] == "1"
        #else
        ProcessInfo.processInfo.arguments.contains("-uitesting-feed-image-diagnostics")
        #endif
    }

    struct PixelSize: Equatable, Sendable {
        var width: Int
        var height: Int

        var label: String { "\(width)×\(height)px" }
    }

    struct StageReport: Equatable, Sendable {
        var stage: String
        var url: String?
        var httpStatus: Int?
        var byteCount: Int?
        var pixelSize: PixelSize?
        var uiImagePointSize: CGSize?
        var uiImageScale: CGFloat?
        var displayPoints: CGSize?
        var displayPixels: PixelSize?
        var interpolation: String?
        var resizingNote: String?
        var fidelityNote: String?
    }

    static func pixelSize(of data: Data) -> PixelSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0 else { return nil }
        return PixelSize(width: width, height: height)
    }

    static func pixelSize(of image: UIImage) -> PixelSize? {
        if let cg = image.cgImage {
            return PixelSize(width: cg.width, height: cg.height)
        }
        let w = Int((image.size.width * image.scale).rounded())
        let h = Int((image.size.height * image.scale).rounded())
        guard w > 0, h > 0 else { return nil }
        return PixelSize(width: w, height: h)
    }

    /// Layout math used by ``AspectFitMediaView`` (width-driven, height-capped).
    static func displaySize(
        imagePixel: PixelSize,
        containerWidthPoints: CGFloat,
        maxHeightPoints: CGFloat,
        screenScale: CGFloat
    ) -> (points: CGSize, pixels: PixelSize) {
        let aspect = CGFloat(imagePixel.width) / CGFloat(imagePixel.height)
        var width = containerWidthPoints
        var height = width / aspect
        if height > maxHeightPoints {
            height = maxHeightPoints
            width = height * aspect
        }
        let px = PixelSize(
            width: Int((width * screenScale).rounded()),
            height: Int((height * screenScale).rounded())
        )
        return (CGSize(width: width, height: height), px)
    }

    static func compare(
        sourcePixels: PixelSize,
        displayPixels: PixelSize
    ) -> String {
        let widthRatio = Double(displayPixels.width) / Double(sourcePixels.width)
        let heightRatio = Double(displayPixels.height) / Double(sourcePixels.height)
        if widthRatio > 1.01 || heightRatio > 1.01 {
            return String(
                format: "UPSCALE at render — display needs %.2f× width / %.2f× height vs bitmap",
                widthRatio,
                heightRatio
            )
        }
        if widthRatio < 0.99 || heightRatio < 0.99 {
            return String(
                format: "Downscale at render — display is %.2f× width / %.2f× height of bitmap (expected; use high interpolation)",
                widthRatio,
                heightRatio
            )
        }
        return "1:1 pixel match at display"
    }

    static func log(_ report: StageReport) {
        guard isEnabled else { return }
        var parts: [String] = ["[image-fidelity] \(report.stage)"]
        if let url = report.url { parts.append("url=\(url)") }
        if let status = report.httpStatus { parts.append("http=\(status)") }
        if let bytes = report.byteCount { parts.append("bytes=\(bytes)") }
        if let px = report.pixelSize { parts.append("pixels=\(px.label)") }
        if let size = report.uiImagePointSize {
            parts.append("uiImage.size=\(Int(size.width))×\(Int(size.height))pt")
        }
        if let scale = report.uiImageScale { parts.append("uiImage.scale=\(scale)") }
        if let pts = report.displayPoints {
            parts.append("display=\(Int(pts.width))×\(Int(pts.height))pt")
        }
        if let dpx = report.displayPixels { parts.append("displayPx=\(dpx.label)") }
        if let interp = report.interpolation { parts.append("interpolation=\(interp)") }
        if let note = report.resizingNote { parts.append("resize=\(note)") }
        if let note = report.fidelityNote { parts.append("fidelity=\(note)") }
        AppLog.networking.info("\(parts.joined(separator: " | "), privacy: .public)")
    }

    /// Full offline probe for a downloaded (or synthetic) payload — used by tests + DEBUG.
    static func probePipeline(
        label: String,
        data: Data,
        url: String?,
        httpStatus: Int?,
        decodeScale: CGFloat,
        containerWidthPoints: CGFloat,
        maxHeightPoints: CGFloat,
        screenScale: CGFloat,
        webFeedThumbWidth: Int = 800
    ) -> [StageReport] {
        var reports: [StageReport] = []

        let downloaded = pixelSize(of: data)
        reports.append(
            StageReport(
                stage: "\(label)/http-bytes",
                url: url,
                httpStatus: httpStatus,
                byteCount: data.count,
                pixelSize: downloaded,
                resizingNote: "no client resize yet"
            )
        )

        let image = UIImage(data: data, scale: decodeScale)
        let decodedPixels = image.flatMap(pixelSize(of:))
        reports.append(
            StageReport(
                stage: "\(label)/decoded-uiimage",
                url: url,
                byteCount: data.count,
                pixelSize: decodedPixels,
                uiImagePointSize: image?.size,
                uiImageScale: image?.scale,
                resizingNote: "UIImage(data:scale:\(decodeScale))"
            )
        )

        if let decodedPixels {
            let display = displaySize(
                imagePixel: decodedPixels,
                containerWidthPoints: containerWidthPoints,
                maxHeightPoints: maxHeightPoints,
                screenScale: screenScale
            )
            let fidelity = compare(sourcePixels: decodedPixels, displayPixels: display.pixels)
            reports.append(
                StageReport(
                    stage: "\(label)/swiftui-render",
                    pixelSize: decodedPixels,
                    uiImagePointSize: image?.size,
                    uiImageScale: image?.scale,
                    displayPoints: display.points,
                    displayPixels: display.pixels,
                    interpolation: "high",
                    resizingNote: "aspectFit width-driven maxHeight=\(Int(maxHeightPoints))",
                    fidelityNote: fidelity
                )
            )

            // Web feed-thumb preset comparison (width=800, quality=75).
            let webWidth = min(webFeedThumbWidth, decodedPixels.width)
            let webHeight = Int(
                (Double(webWidth) * Double(decodedPixels.height) / Double(decodedPixels.width))
                    .rounded()
            )
            let webPixels = PixelSize(width: webWidth, height: webHeight)
            let webDisplay = displaySize(
                imagePixel: webPixels,
                containerWidthPoints: containerWidthPoints,
                maxHeightPoints: min(maxHeightPoints, 440),
                screenScale: screenScale
            )
            reports.append(
                StageReport(
                    stage: "\(label)/web-feed-thumb-equivalent",
                    pixelSize: webPixels,
                    displayPoints: webDisplay.points,
                    displayPixels: webDisplay.pixels,
                    resizingNote: "web preset feed-thumb width=800 quality=75 (or original fallback)",
                    fidelityNote: compare(sourcePixels: webPixels, displayPixels: webDisplay.pixels)
                )
            )
        }

        for report in reports {
            log(report)
        }
        return reports
    }
}
