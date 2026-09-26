import UIKit
import XCTest
@testable import TradeTraxs

final class ChatImagePreparationTests: XCTestCase {
    func testLandscapeCameraPhotoCapsAt2560By1920() {
        let size = MediaImagePreparation.chatOutputPixelSize(width: 4032, height: 3024)
        XCTAssertEqual(size.width, 2560, accuracy: 0.1)
        XCTAssertEqual(size.height, 1920, accuracy: 0.1)
    }

    func testPortraitCameraPhotoCapsAt1920By2560() {
        let size = MediaImagePreparation.chatOutputPixelSize(width: 3024, height: 4032)
        XCTAssertEqual(size.width, 1920, accuracy: 0.1)
        XCTAssertEqual(size.height, 2560, accuracy: 0.1)
    }

    func testImageAlreadyWithinCapKeepsOriginalDimensions() {
        let small = MediaImagePreparation.chatOutputPixelSize(width: 800, height: 600)
        XCTAssertEqual(small.width, 800, accuracy: 0.1)
        XCTAssertEqual(small.height, 600, accuracy: 0.1)

        let exact = MediaImagePreparation.chatOutputPixelSize(width: 2560, height: 1440)
        XCTAssertEqual(exact.width, 2560, accuracy: 0.1)
        XCTAssertEqual(exact.height, 1440, accuracy: 0.1)
    }

    func testAspectRatioIsPreserved() {
        let size = MediaImagePreparation.chatOutputPixelSize(width: 4000, height: 3000)
        let sourceAspect = 4000.0 / 3000.0
        let outputAspect = size.width / size.height
        XCTAssertEqual(outputAspect, sourceAspect, accuracy: 0.01)
        XCTAssertLessThanOrEqual(max(size.width, size.height), MediaImagePreparation.chatMaxLongestEdge)
    }

    func testChatJPEGQualityIs082() {
        XCTAssertEqual(MediaImagePreparation.chatJPEGQuality, 0.82, accuracy: 0.0001)
        XCTAssertEqual(MediaImagePreparation.chatMaxLongestEdge, 2560, accuracy: 0.1)
    }

    func testDownscaleEncodesOneJPEGAtTargetSize() {
        let source = makeSolidImage(width: 3000, height: 2000, orientation: .up)
        guard let data = MediaImagePreparation.chatJPEGData(from: source) else {
            XCTFail("Expected JPEG data")
            return
        }
        XCTAssertEqual(data.prefix(2), Data([0xFF, 0xD8]))
        guard let decoded = UIImage(data: data) else {
            XCTFail("Expected decodable JPEG")
            return
        }
        let pixels = MediaImageOrientation.pixelSize(of: decoded)
        XCTAssertEqual(pixels.width, 2560, accuracy: 1)
        XCTAssertEqual(pixels.height, 1706, accuracy: 1)
        XCTAssertEqual(decoded.imageOrientation, .up)
    }

    func testSmallImageIsNotUpscaled() {
        let source = makeSolidImage(width: 640, height: 480, orientation: .up)
        guard let data = MediaImagePreparation.chatJPEGData(from: source),
              let decoded = UIImage(data: data)
        else {
            XCTFail("Expected JPEG data")
            return
        }
        let pixels = MediaImageOrientation.pixelSize(of: decoded)
        XCTAssertEqual(pixels.width, 640, accuracy: 1)
        XCTAssertEqual(pixels.height, 480, accuracy: 1)
    }

    func testOrientationIsBakedBeforeSizing() {
        let source = makeSolidImage(width: 100, height: 400, orientation: .right)
        let visual = MediaImageOrientation.pixelSize(of: source)
        XCTAssertEqual(visual.width, 400, accuracy: 0.5)
        XCTAssertEqual(visual.height, 100, accuracy: 0.5)

        guard let data = MediaImagePreparation.chatJPEGData(from: source),
              let decoded = UIImage(data: data)
        else {
            XCTFail("Expected JPEG data")
            return
        }
        let pixels = MediaImageOrientation.pixelSize(of: decoded)
        XCTAssertEqual(decoded.imageOrientation, .up)
        XCTAssertEqual(pixels.width, 400, accuracy: 1)
        XCTAssertEqual(pixels.height, 100, accuracy: 1)
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
        guard let cgImage = upright.cgImage else { return upright }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }
}
