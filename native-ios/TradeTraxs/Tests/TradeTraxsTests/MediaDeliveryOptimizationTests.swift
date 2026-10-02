import XCTest
@testable import TradeTraxs

final class MediaDeliveryOptimizationTests: XCTestCase {
    func testFeedThumbDeliveryUsesObjectPublicNotRenderTransform() {
        let object = URL(
            string: "https://example.supabase.co/storage/v1/object/public/posts/user123/opt/photo.jpg"
        )!
        let thumb = StorageImageTransform.optimizedURL(for: object, preset: .feedThumb)
        XCTAssertTrue(thumb.path.contains("/storage/v1/object/public/"))
        XCTAssertFalse(thumb.path.contains("/storage/v1/render/image/public/"))
        XCTAssertFalse(thumb.absoluteString.contains("width="))
    }

    func testFullResolutionDeliverySkipsTransformPreset() {
        XCTAssertNil(StorageImageTransform.preset(for: .postImage, delivery: .fullResolution))
        XCTAssertNil(StorageImageTransform.preset(for: .tradeScreenshot, delivery: .fullResolution))
    }

    func testFeedDetailPresetStillMapsButDeliversObjectURL() {
        let preset = StorageImageTransform.preset(for: .postImage, delivery: .feedDetail)
        XCTAssertEqual(preset, .feedDetail)
        let object = URL(
            string: "https://example.supabase.co/storage/v1/object/public/posts/u/opt/x.jpg"
        )!
        let url = StorageImageTransform.optimizedURL(for: object, preset: .feedDetail)
        XCTAssertTrue(url.path.contains("/storage/v1/object/public/"))
        XCTAssertFalse(url.absoluteString.contains("width=1280"))
    }

    func testFeedDisplayCacheRevisionBumpedForObjectDelivery() {
        XCTAssertEqual(StorageImageTransform.feedDisplayCacheRevision, 4)
    }

    func testPhotosPickerDecodeCapPreventsTwelveKDecode() {
        XCTAssertEqual(PhotosPickerImageDecoder.pickerDecodeMaxPixelSize, 4096)
        XCTAssertLessThan(PhotosPickerImageDecoder.pickerDecodeMaxPixelSize, 12_000)
    }

    func testStoryVideoLimitsMatchPublishPipeline() {
        XCTAssertEqual(MediaVideoPreparation.Limits.story.maxDurationSeconds, 10)
        XCTAssertEqual(MediaVideoPreparation.Limits.story.maxFinalUploadBytes, 15 * 1024 * 1024)
    }

    func testDeliveryObjectURLStripsRenderPathForFallback() {
        let render = URL(
            string: "https://example.supabase.co/storage/v1/render/image/public/posts/u/opt/x.jpg?width=640"
        )!
        let object = StorageImageTransform.deliveryObjectURL(for: render)
        XCTAssertTrue(object.path.contains("/storage/v1/object/public/"))
        XCTAssertFalse(object.path.contains("render/image"))
    }
}
