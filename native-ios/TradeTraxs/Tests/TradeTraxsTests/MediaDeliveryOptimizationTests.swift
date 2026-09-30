import XCTest
@testable import TradeTraxs

final class MediaDeliveryOptimizationTests: XCTestCase {
    func testOptimizedStorageFeedThumbUsesRenderTransformNotRawObject() {
        let object = URL(
            string: "https://example.supabase.co/storage/v1/object/public/posts/user123/opt/photo.jpg"
        )!
        let thumb = StorageImageTransform.optimizedURL(for: object, preset: .feedThumb)
        XCTAssertTrue(thumb.path.contains("/storage/v1/render/image/public/"))
        XCTAssertTrue(thumb.absoluteString.contains("width=640"))
        XCTAssertFalse(thumb.path.contains("/opt/") && !thumb.path.contains("render/image"))
    }

    func testFullResolutionDeliverySkipsTransformPreset() {
        XCTAssertNil(StorageImageTransform.preset(for: .postImage, delivery: .fullResolution))
        XCTAssertNil(StorageImageTransform.preset(for: .tradeScreenshot, delivery: .fullResolution))
    }

    func testFeedDetailStillRequestsHigherWidthPreset() {
        let preset = StorageImageTransform.preset(for: .postImage, delivery: .feedDetail)
        XCTAssertEqual(preset, .feedDetail)
        let object = URL(
            string: "https://example.supabase.co/storage/v1/object/public/posts/u/opt/x.jpg"
        )!
        let url = StorageImageTransform.optimizedURL(for: object, preset: .feedDetail)
        XCTAssertTrue(url.absoluteString.contains("width=1280"))
    }

    func testFeedDisplayCacheRevisionBumpedForStableBuckets() {
        XCTAssertEqual(StorageImageTransform.feedDisplayCacheRevision, 3)
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
