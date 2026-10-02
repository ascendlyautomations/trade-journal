import SwiftUI
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
                textFill: .fromPreset(.white)
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

    @MainActor
    func testOverlayScaleClampsToEditorBounds() {
        let viewModel = StoryEditorViewModel(sourceImage: makeSolidImage(size: CGSize(width: 100, height: 100)))
        viewModel.beginAddingText()
        guard let id = viewModel.canvas.selectedTextID else {
            XCTFail("Expected overlay")
            return
        }
        viewModel.updateDraftText("Hi")
        viewModel.finishEditingText()
        viewModel.updateOverlayScale(id: id, scale: 10)
        XCTAssertEqual(Double(viewModel.canvas.textOverlays.first?.scale ?? 0), 3, accuracy: 0.001)
        viewModel.updateOverlayScale(id: id, scale: 0.01)
        XCTAssertEqual(Double(viewModel.canvas.textOverlays.first?.scale ?? 0), 0.5, accuracy: 0.001)
    }

    func testTrashHitZoneIsLargerThanTheIconAndUsesCanvasCoordinates() {
        let canvas = CGSize(width: 360, height: 640)
        let icon = StoryTextDragDeleteMetrics.visibleIconFrame(canvasSize: canvas)
        let zone = StoryTextDragDeleteMetrics.hitZone(canvasSize: canvas)

        XCTAssertEqual(icon.width, StoryTextDragDeleteMetrics.iconSize)
        XCTAssertGreaterThan(zone.width, icon.width)
        XCTAssertGreaterThan(zone.height, icon.height)
        XCTAssertTrue(zone.contains(icon))

        let besideIcon = CGPoint(x: icon.minX - 20, y: icon.midY)
        XCTAssertFalse(icon.contains(besideIcon))
        XCTAssertTrue(StoryTextDragDeleteMetrics.containsElementCenter(besideIcon, canvasSize: canvas))

        let canvasCenter = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        XCTAssertFalse(StoryTextDragDeleteMetrics.containsElementCenter(canvasCenter, canvasSize: canvas))

        let iconCenter = CGPoint(x: icon.midX, y: icon.midY)
        XCTAssertTrue(StoryTextDragDeleteMetrics.containsElementCenter(iconCenter, canvasSize: canvas))
    }

    @MainActor
    func testVideoEditorKeepsMultipleTextOverlaysAndDropsBlankText() {
        let viewModel = StoryEditorViewModel(videoURL: URL(fileURLWithPath: "/tmp/story.mp4"))
        viewModel.beginAddingText()
        viewModel.updateDraftText("First")
        viewModel.finishEditingText()
        viewModel.beginAddingText()
        viewModel.updateDraftText("Second")
        viewModel.updateOverlayPosition(
            id: viewModel.canvas.selectedTextID!,
            normalizedCenter: CGPoint(x: 0.2, y: 0.7)
        )
        viewModel.finishEditingText()
        viewModel.beginAddingText()
        viewModel.finishEditingText()

        XCTAssertEqual(viewModel.canvas.textOverlays.count, 2)
        XCTAssertEqual(viewModel.publishableTextOverlays.map(\.text), ["First", "Second"])
        XCTAssertEqual(viewModel.publishableTextOverlays[1].normalizedCenter.x, 0.2, accuracy: 0.001)
        XCTAssertNil(viewModel.renderFinalImage())
    }

    @MainActor
    func testVideoTextOverlayRecordRoundTripsStyleAndPosition() throws {
        let overlay = StoryTextOverlay(
            text: "Hold",
            normalizedCenter: CGPoint(x: 0.33, y: 0.71),
            scale: 1.4,
            rotationRadians: 0.25,
            textFill: StoryTextFill(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8),
            alignment: .leading,
            showsBackground: true
        )
        let data = try JSONEncoder().encode(StoryTextOverlayRecord(overlay))
        let decoded = try JSONDecoder().decode(StoryTextOverlayRecord.self, from: data)
        let restored = decoded.storyTextOverlay()

        XCTAssertEqual(restored.text, "Hold")
        XCTAssertEqual(restored.normalizedCenter.x, 0.33, accuracy: 0.001)
        XCTAssertEqual(restored.normalizedCenter.y, 0.71, accuracy: 0.001)
        XCTAssertEqual(restored.scale, 1.4, accuracy: 0.001)
        XCTAssertEqual(restored.rotationRadians, 0.25, accuracy: 0.001)
        XCTAssertEqual(restored.alignment, .leading)
        XCTAssertTrue(restored.showsBackground)
        XCTAssertEqual(restored.textFill.red, 0.2, accuracy: 0.001)
    }

    func testVideoTextPlacementKeepsCenterAndTracksVideoPixels() {
        let video = CGSize(width: 1080, height: 1920)
        let viewer = CGSize(width: 390, height: 844)
        let center = StoryTextOverlayPlacement.viewerNormalizedCenter(
            composerNormalized: CGPoint(x: 0.5, y: 0.5),
            videoPixelSize: video,
            viewerSize: viewer
        )
        XCTAssertEqual(center.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.01)

        let matchingViewer = CGSize(width: 360, height: 640)
        let shifted = StoryTextOverlayPlacement.viewerNormalizedCenter(
            composerNormalized: CGPoint(x: 0.2, y: 0.3),
            videoPixelSize: video,
            viewerSize: matchingViewer
        )
        XCTAssertEqual(shifted.x, 0.2, accuracy: 0.01)
        XCTAssertEqual(shifted.y, 0.3, accuracy: 0.01)

        let cropped = StoryTextOverlayPlacement.viewerNormalizedCenter(
            composerNormalized: CGPoint(x: 0.2, y: 0.3),
            videoPixelSize: video,
            viewerSize: viewer
        )
        XCTAssertNotEqual(cropped.x, 0.2, accuracy: 0.02)
        XCTAssertEqual(cropped.y, 0.3, accuracy: 0.02)

        let unknownSize = StoryTextOverlayPlacement.viewerNormalizedCenter(
            composerNormalized: CGPoint(x: 0.2, y: 0.3),
            videoPixelSize: .zero,
            viewerSize: viewer
        )
        XCTAssertEqual(unknownSize.x, 0.2, accuracy: 0.001)
        XCTAssertEqual(unknownSize.y, 0.3, accuracy: 0.001)
    }

    private func makeSolidImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
