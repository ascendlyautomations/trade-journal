import XCTest
@testable import TradeTraxs

final class ImageCropMathTests: XCTestCase {
    func testClampOffsetReturnsZeroWhenImageFits() {
        let offset = ImageCropMath.clampOffset(
            imageWidth: 800,
            imageHeight: 600,
            frameWidth: 400,
            frameHeight: 300,
            zoom: 1,
            offset: CGSize(width: 40, height: -20)
        )
        XCTAssertEqual(offset, .zero)
    }

    func testFeedCardUsesNaturalHeightForLandscape() {
        let presentation = ContentImagePresentation(
            presentationAspectRatio: 16 / 9,
            normalizedCrop: nil,
            aspectMode: .original
        )
        let metrics = FeedMediaLayout.frameMetrics(
            containerWidth: 390,
            imageAspect: 16 / 9,
            presentation: presentation
        )
        XCTAssertFalse(metrics.usesFillCrop)
        XCTAssertEqual(metrics.containerHeight, 390 / (16 / 9), accuracy: 0.5)
    }

    func testFeedCardCapsTallOriginalAtFourToFive() {
        let imageAspect = 1179.0 / 2556.0
        let presentation = ContentImagePresentation.inferredLegacy(imageAspect: imageAspect)
        let metrics = FeedMediaLayout.frameMetrics(
            containerWidth: 390,
            imageAspect: imageAspect,
            presentation: presentation
        )
        XCTAssertTrue(metrics.usesFillCrop)
        XCTAssertEqual(metrics.containerWidth, 390, accuracy: 0.5)
        XCTAssertEqual(metrics.containerHeight, 390 / (4.0 / 5.0), accuracy: 0.5)
    }

    func testSquareUsesNaturalSquareHeight() {
        let presentation = ContentImagePresentation(
            presentationAspectRatio: 1,
            normalizedCrop: nil,
            aspectMode: .original
        )
        let metrics = FeedMediaLayout.frameMetrics(
            containerWidth: 390,
            imageAspect: 1,
            presentation: presentation
        )
        XCTAssertFalse(metrics.usesFillCrop)
        XCTAssertEqual(metrics.containerHeight, 390, accuracy: 0.5)
    }

    func testOriginalDetailDoesNotCapHeight() {
        let metrics = AdaptiveMediaLayout.frameMetrics(
            containerWidth: 390,
            imageAspect: 1179.0 / 2556.0,
            displayMode: .originalDetail
        )
        XCTAssertFalse(metrics.usesFillCrop)
        XCTAssertEqual(metrics.containerHeight, 390 / (1179.0 / 2556.0), accuracy: 0.5)
    }

    func testRequiresFillCropWhenTallerThanFourToFive() {
        XCTAssertTrue(
            FeedMediaLayout.requiresFillCrop(
                imageAspect: 1179.0 / 2556.0,
                aspectOption: .original
            )
        )
        XCTAssertFalse(
            FeedMediaLayout.requiresFillCrop(
                imageAspect: 4.0 / 5.0,
                aspectOption: .original
            )
        )
    }

    func testNormalizedCropFromEditorTopBias() {
        let pixelSize = CGSize(width: 390, height: 844)
        let viewport = CGSize(width: 390, height: 487.5)
        let transform = ImageCropTransform(
            zoom: 1,
            offset: CGSize(width: 0, height: 120)
        )
        let crop = ContentImagePresentation.normalizedCropFromEditor(
            imagePixelSize: pixelSize,
            viewportSize: viewport,
            transform: transform
        )
        XCTAssertLessThan(crop.y, 0.15)
    }
}
