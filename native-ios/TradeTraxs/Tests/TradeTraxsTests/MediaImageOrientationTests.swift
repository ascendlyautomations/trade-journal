import UIKit
import XCTest
@testable import TradeTraxs

final class MediaImageOrientationTests: XCTestCase {
    func testNormalizedImageIsUpOrientation() {
        let source = makeSolidImage(
            width: 400,
            height: 800,
            orientation: .right
        )
        let normalized = MediaImageOrientation.normalized(source)
        XCTAssertEqual(normalized.imageOrientation, .up)
        XCTAssertEqual(normalized.scale, 1)
    }

    func testRightOrientationSwapsPixelDimensions() {
        let source = makeSolidImage(
            width: 400,
            height: 800,
            orientation: .right
        )
        let pixelSize = MediaImageOrientation.pixelSize(of: source)
        XCTAssertEqual(pixelSize.width, 800, accuracy: 0.5)
        XCTAssertEqual(pixelSize.height, 400, accuracy: 0.5)
    }

    func testPortraitScreenshotAspectUsesVisualDimensions() {
        let screenshot = makeSolidImage(
            width: 1179,
            height: 2556,
            orientation: .up
        )
        let aspect = MediaImageOrientation.aspectRatio(of: screenshot)
        XCTAssertEqual(aspect, 1179.0 / 2556.0, accuracy: 0.001)
    }

    func testCropRendererProducesUprightJPEG() {
        let source = makeSolidImage(
            width: 600,
            height: 900,
            orientation: .down
        )
        let rendered = ImageCropRenderer.render(
            sourceImage: source,
            preset: .socialContent,
            aspectOption: .original,
            transform: .default
        )
        XCTAssertNotNil(rendered)
        XCTAssertEqual(rendered?.imageOrientation, .up)
        let pixels = MediaImageOrientation.pixelSize(of: rendered!)
        XCTAssertGreaterThan(pixels.width, 0)
        XCTAssertGreaterThan(pixels.height, 0)
    }

    func testExportFeedCropSquareFromTallSource() {
        let source = makeSolidImage(width: 1179, height: 2556, orientation: .up)
        let viewport = FeedMediaLayout.editorViewportSize(
            containerWidth: 390,
            imagePixelSize: CGSize(width: 1179, height: 2556),
            aspectOption: .square
        )
        let exported = ImageCropRenderer.exportFeedCrop(
            sourceImage: source,
            aspectOption: .square,
            viewportSize: viewport,
            transform: .default
        )
        XCTAssertNotNil(exported)
        let pixels = MediaImageOrientation.pixelSize(of: exported!)
        XCTAssertEqual(pixels.width, pixels.height, accuracy: 1)
        let aspect = pixels.width / pixels.height
        XCTAssertEqual(aspect, 1, accuracy: 0.01)
    }

    func testExportFeedCropPortraitAspectRatio() {
        let source = makeSolidImage(width: 1200, height: 2400, orientation: .up)
        let viewport = FeedMediaLayout.editorViewportSize(
            containerWidth: 390,
            imagePixelSize: CGSize(width: 1200, height: 2400),
            aspectOption: .portrait
        )
        let exported = ImageCropRenderer.exportFeedCrop(
            sourceImage: source,
            aspectOption: .portrait,
            viewportSize: viewport,
            transform: .default
        )
        XCTAssertNotNil(exported)
        let pixels = MediaImageOrientation.pixelSize(of: exported!)
        let aspect = pixels.width / pixels.height
        XCTAssertEqual(aspect, 4.0 / 5.0, accuracy: 0.02)
    }

    func testExportFeedCropTopBiasDiffersFromBottomBias() {
        let source = makeSolidImage(width: 1179, height: 2556, orientation: .up)
        let viewport = FeedMediaLayout.editorViewportSize(
            containerWidth: 390,
            imagePixelSize: CGSize(width: 1179, height: 2556),
            aspectOption: .square
        )
        let topCrop = ImageCropRenderer.exportFeedCrop(
            sourceImage: source,
            aspectOption: .square,
            viewportSize: viewport,
            transform: ImageCropTransform(zoom: 1, offset: CGSize(width: 0, height: 120))
        )
        let bottomCrop = ImageCropRenderer.exportFeedCrop(
            sourceImage: source,
            aspectOption: .square,
            viewportSize: viewport,
            transform: ImageCropTransform(zoom: 1, offset: CGSize(width: 0, height: -120))
        )
        XCTAssertNotNil(topCrop)
        XCTAssertNotNil(bottomCrop)
        let topPixels = MediaImageOrientation.pixelSize(of: topCrop!)
        let bottomPixels = MediaImageOrientation.pixelSize(of: bottomCrop!)
        XCTAssertEqual(topPixels.width, topPixels.height, accuracy: 2)
        XCTAssertNotEqual(topPixels, bottomPixels)
    }

    func testExportFeedCropOriginalWideUsesFullImage() {
        let source = makeSolidImage(width: 1600, height: 900, orientation: .up)
        let viewport = FeedMediaLayout.editorViewportSize(
            containerWidth: 390,
            imagePixelSize: CGSize(width: 1600, height: 900),
            aspectOption: .original
        )
        let exported = ImageCropRenderer.exportFeedCrop(
            sourceImage: source,
            aspectOption: .original,
            viewportSize: viewport,
            transform: .default
        )
        XCTAssertNotNil(exported)
        let pixels = MediaImageOrientation.pixelSize(of: exported!)
        XCTAssertEqual(pixels.width, 1600, accuracy: 1)
        XCTAssertEqual(pixels.height, 900, accuracy: 1)
    }

    private func makeSolidImage(
        width: Int,
        height: Int,
        orientation: UIImage.Orientation
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let upright = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let cgImage = upright.cgImage else {
            return upright
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }
}
