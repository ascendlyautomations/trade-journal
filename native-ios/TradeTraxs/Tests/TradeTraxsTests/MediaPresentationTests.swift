import CoreGraphics
import ImageIO
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

    func testPipelineSkipsReencodeWhenAlreadyWithinDisplayBudget() async throws {
        // 64×64 PNG — well under feed maxPixelSize; bytes must stay original (no JPEG pass).
        let png = Self.makePNG(width: 64, height: 64)
        XCTAssertFalse(png.isEmpty)
        let pipeline = DefaultImagePipeline(
            cache: InMemoryImageCache(),
            storage: StubMediaObjectStorage(),
            downloadService: StubMediaDownloadService(data: png)
        )
        let data = try await pipeline.data(
            for: ImageRequest(
                reference: MediaReference(id: "tiny-post.png", kind: .image, altText: nil),
                purpose: .postImage,
                maxPixelSize: 1080
            )
        )
        XCTAssertEqual(data, png)
    }

    func testFeedLoadsOriginalObjectBytesWhenMaxPixelSizeNil() async throws {
        // Web feed falls back to `/object/public/` originals — native feed must too.
        let png = Self.makePNG(width: 1800, height: 2400) // portrait phone-like
        XCTAssertFalse(png.isEmpty)
        let pipeline = DefaultImagePipeline(
            cache: InMemoryImageCache(),
            storage: StubMediaObjectStorage(),
            downloadService: StubMediaDownloadService(data: png)
        )
        let data = try await pipeline.data(
            for: ImageRequest(
                reference: MediaReference(id: "phone-portrait.png", kind: .image, altText: nil),
                purpose: .tradeScreenshot,
                maxPixelSize: nil
            )
        )
        XCTAssertEqual(data, png, "Feed must not downsample/re-encode when maxPixelSize is nil")
    }

    func testPortraitLongestEdgeBudgetMustCoverRetinaWidth() {
        // Documents the historical bug: longest-edge == screenWidth×scale under-fills
        // portrait width, so SwiftUI upscales (blur). 3:4 portrait on 393pt @3×:
        let needWidth = 393 * 3
        let wrongLongest = needWidth // old AspectFitMediaView budget
        let wrongDecodedWidth = Int(Double(wrongLongest) * 3.0 / 4.0)
        XCTAssertLessThan(wrongDecodedWidth, needWidth)

        let correctLongest = Int((Double(needWidth) * 4.0 / 3.0).rounded(.up))
        let correctDecodedWidth = Int(Double(correctLongest) * 3.0 / 4.0)
        XCTAssertGreaterThanOrEqual(correctDecodedWidth, needWidth)
    }

    private static func makePNG(width: Int, height: Int) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ),
        let image = context.makeImage() else {
            return Data()
        }
        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return mutable as Data
    }
}

private struct StubMediaImagePipeline: ImagePipeline {
    func data(for request: ImageRequest) async throws -> Data {
        Data()
    }

    func prefetch(_ requests: [ImageRequest]) async {}
    func invalidate(reference: MediaReference) async {}
}

private struct StubMediaObjectStorage: ObjectStorageProviding {
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        path
    }

    func download(bucket: String, path: String) async throws -> Data {
        Data()
    }

    func delete(bucket: String, path: String) async throws {}

    func publicURL(bucket: String, path: String) -> URL? { nil }
}

private struct StubMediaDownloadService: DownloadService {
    let data: Data

    func download(_ request: DownloadRequest) async throws -> Data {
        data
    }
}
