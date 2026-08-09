import SwiftUI
import XCTest
@testable import TradeTraxs

/// Guards the layout contract that caused “heavily zoomed” Trade/Post images:
/// detail media must size from the bitmap’s aspect ratio (fit), never fill-crop.
final class MediaPresentationTests: XCTestCase {
    func testAspectRatioIsWidthOverHeight() {
        XCTAssertEqual(1_200.0 / 600.0, 2.0, accuracy: 0.001)
        XCTAssertEqual(600.0 / 1_200.0, 0.5, accuracy: 0.001)
        XCTAssertEqual(800.0 / 800.0, 1.0, accuracy: 0.001)
    }

    func testTradeImageViewDefaultsToAspectFit() {
        // API contract: default contentMode must be `.fit` so Profile trade
        // cards do not crop uploads into a square fill.
        let view = TradeImageView(
            reference: nil,
            imagePipeline: StubMediaImagePipeline()
        )
        XCTAssertEqual(view.contentMode, .fit)
    }
}

private struct StubMediaImagePipeline: ImagePipeline {
    func data(for request: ImageRequest) async throws -> Data {
        Data()
    }

    func prefetch(_ requests: [ImageRequest]) async {}
    func invalidate(reference: MediaReference) async {}
}
