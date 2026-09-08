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
