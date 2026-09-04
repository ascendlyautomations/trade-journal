import XCTest
@testable import TradeTraxs

final class StoryEditorTests: XCTestCase {
    func testRendererProducesNineBySixteenOutput() {
        let image = makeSolidImage(size: CGSize(width: 800, height: 600))
        var canvas = StoryCanvasState()
        canvas.imageScale = 1.2
        canvas.textOverlays = [
            StoryTextOverlay(
                text: "TEST",
                normalizedCenter: CGPoint(x: 0.5, y: 0.5),
                color: .white
            ),
        ]
        let canvasSize = CGSize(width: 360, height: 640)
        let rendered = StoryImageRenderer.render(
            sourceImage: image,
            canvas: canvas,
            canvasSize: canvasSize
        )
        XCTAssertNotNil(rendered)
        XCTAssertEqual(Double(rendered!.size.width), 1080, accuracy: 0.5)
        XCTAssertEqual(Double(rendered!.size.height), 1920, accuracy: 0.5)
    }

    func testImageLayoutAspectFitAtUnitScale() {
        let canvasSize = CGSize(width: 360, height: 640)
        let imageSize = CGSize(width: 1200, height: 800)
        let rect = StoryImageLayout.drawRect(
            imageSize: imageSize,
            canvasSize: canvasSize,
            scale: 1,
            offset: .zero
        )
        XCTAssertLessThanOrEqual(rect.width, canvasSize.width)
        XCTAssertLessThanOrEqual(rect.height, canvasSize.height)
        XCTAssertEqual(rect.midX, canvasSize.width / 2, accuracy: 0.5)
        XCTAssertEqual(rect.midY, canvasSize.height / 2, accuracy: 0.5)
    }

    func testImageLayoutAllowsZoomOutAndFreePan() {
        let canvasSize = CGSize(width: 360, height: 640)
        let imageSize = CGSize(width: 1200, height: 800)
        let rect = StoryImageLayout.drawRect(
            imageSize: imageSize,
            canvasSize: canvasSize,
            scale: 0.5,
            offset: CGSize(width: 80, height: -120)
        )
        XCTAssertLessThan(rect.width, canvasSize.width)
        XCTAssertLessThan(rect.height, canvasSize.height)
        XCTAssertGreaterThan(rect.minX, 0)
        XCTAssertLessThan(rect.maxY, canvasSize.height)
    }

    private func makeSolidImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
