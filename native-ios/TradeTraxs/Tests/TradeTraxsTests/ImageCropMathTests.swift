import XCTest
@testable import TradeTraxs

final class ImageCropMathTests: XCTestCase {
    func testContentCropSelectorIsSquarePortraitAndLandscape() {
        XCTAssertEqual(
            ImageCropAspectOption.feedAspectOptions,
            [.square, .portrait, .landscape]
        )
        XCTAssertFalse(ImageCropAspectOption.feedAspectOptions.contains(.original))
        XCTAssertEqual(ImageCropEditorPreset.socialContent.defaultAspectOption, .portrait)
        XCTAssertEqual(ImageCropEditorPreset.tradeScreenshot.defaultAspectOption, .portrait)
        XCTAssertEqual(ImageCropEditorPreset.socialContent.allowedAspectOptions, ImageCropAspectOption.feedAspectOptions)
        XCTAssertEqual(ImageCropEditorPreset.tradeScreenshot.allowedAspectOptions, ImageCropAspectOption.feedAspectOptions)
        XCTAssertEqual(ImageCropEditorPreset.avatar.allowedAspectOptions, [.square])
        XCTAssertEqual(ImageCropEditorPreset.room.allowedAspectOptions, [.square])
        XCTAssertEqual(ImageCropAspectOption.square.title, "1:1")
        XCTAssertEqual(ImageCropAspectOption.portrait.title, "4:5")
        XCTAssertEqual(ImageCropAspectOption.landscape.title, "16:9")
    }

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

    func testFeedWithoutExplicitCropUsesDetailLikeMetrics() {
        let imageAspect = 4.0 / 5.0
        let metrics = AdaptiveMediaLayout.frameMetrics(
            containerWidth: 390,
            imageAspect: imageAspect,
            displayMode: .originalDetail
        )
        XCTAssertFalse(metrics.usesFillCrop)
        XCTAssertEqual(metrics.containerHeight, 390 / imageAspect, accuracy: 0.5)
    }

    func testExplicitLegacyCropRequiresMetadataRect() {
        let withRect = ContentImagePresentation(
            presentationAspectRatio: 4.0 / 5.0,
            normalizedCrop: NormalizedImageCrop(x: 0, y: 0.1, width: 1, height: 0.8),
            aspectMode: .portrait
        )
        XCTAssertNotNil(ContentImagePresentation.explicitLegacyCrop(from: withRect))

        let withoutRect = ContentImagePresentation(
            presentationAspectRatio: 4.0 / 5.0,
            normalizedCrop: nil,
            aspectMode: .portrait,
            sourceWidth: 1179,
            sourceHeight: 2556
        )
        XCTAssertNil(ContentImagePresentation.explicitLegacyCrop(from: withoutRect))
    }

    func testTallImageUsesNaturalHeightInDetailLikeLayout() {
        let imageAspect = 1179.0 / 2556.0
        let metrics = AdaptiveMediaLayout.frameMetrics(
            containerWidth: 390,
            imageAspect: imageAspect,
            displayMode: .originalDetail
        )
        XCTAssertFalse(metrics.usesFillCrop)
        XCTAssertEqual(metrics.containerHeight, 390 / imageAspect, accuracy: 0.5)
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

    func testSquareAspectModeRequiresFramedViewport() {
        let presentation = ContentImagePresentation(
            presentationAspectRatio: 1,
            normalizedCrop: NormalizedImageCrop(x: 0, y: 0.1, width: 1, height: 0.8),
            aspectMode: .square
        )
        let metrics = FeedMediaLayout.frameMetrics(
            containerWidth: 390,
            imageAspect: 16 / 9,
            presentation: presentation
        )
        XCTAssertTrue(metrics.usesFillCrop)
        XCTAssertEqual(metrics.containerHeight, 390, accuracy: 0.5)
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

    func testViewportExportCenteredNotTopBiased() {
        let sourcePixels = CGSize(width: 1179, height: 2556)
        let viewport = FeedMediaLayout.editorViewportSize(
            containerWidth: 390,
            imagePixelSize: sourcePixels,
            aspectOption: .landscape
        )
        let layout = ImageCropViewportMath.layout(
            imagePixelSize: sourcePixels,
            viewportSize: viewport,
            userScale: 1,
            translation: .zero
        )
        let crop = ImageCropViewportMath.sourcePixelCrop(
            layout: layout,
            viewportSize: viewport,
            imagePixelSize: sourcePixels
        )
        let centerY = crop.midY
        let imageMidY = sourcePixels.height / 2
        XCTAssertEqual(centerY, imageMidY, accuracy: sourcePixels.height * 0.05)
    }

    func testViewportExportVerticalPanChangesCropY() {
        let sourcePixels = CGSize(width: 1179, height: 2556)
        let viewport = FeedMediaLayout.editorViewportSize(
            containerWidth: 390,
            imagePixelSize: sourcePixels,
            aspectOption: .square
        )
        let upLayout = ImageCropViewportMath.layout(
            imagePixelSize: sourcePixels,
            viewportSize: viewport,
            userScale: 1,
            translation: CGSize(width: 0, height: 140)
        )
        let downLayout = ImageCropViewportMath.layout(
            imagePixelSize: sourcePixels,
            viewportSize: viewport,
            userScale: 1,
            translation: CGSize(width: 0, height: -140)
        )
        let upCrop = ImageCropViewportMath.sourcePixelCrop(
            layout: upLayout,
            viewportSize: viewport,
            imagePixelSize: sourcePixels
        )
        let downCrop = ImageCropViewportMath.sourcePixelCrop(
            layout: downLayout,
            viewportSize: viewport,
            imagePixelSize: sourcePixels
        )
        XCTAssertNotEqual(upCrop.origin.y, downCrop.origin.y, accuracy: 1)
        XCTAssertLessThan(upCrop.origin.y, downCrop.origin.y)
    }

    func testViewportGeometryInverseMatchesSourceCrop() {
        let sourcePixels = CGSize(width: 1179, height: 2556)
        let viewport = FeedMediaLayout.editorViewportSize(
            containerWidth: 390,
            imagePixelSize: sourcePixels,
            aspectOption: .landscape
        )
        let geometry = CropViewportGeometry(
            sourcePixelSize: sourcePixels,
            viewportSize: viewport,
            userScale: 1.15,
            translation: CGSize(width: 0, height: -80)
        )
        let exported = geometry.sourcePixelCropRect()
        let inverse = geometry.sourceRectBeforeClamp

        XCTAssertEqual(exported.origin.x, max(0, inverse.origin.x), accuracy: 0.5)
        XCTAssertEqual(exported.origin.y, max(0, inverse.origin.y), accuracy: 0.5)
        XCTAssertEqual(exported.midY, geometry.previewSourceCenter, accuracy: 1)
    }
}
