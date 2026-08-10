import ImageIO
import UIKit
import XCTest
@testable import TradeTraxs

/// End-to-end fidelity measurements — identifies the stage where sharpness is lost.
final class ImageFidelityTraceTests: XCTestCase {
    /// Phone-like portrait upload (iPhone 14 logical capture after compressScreenshot cap).
    private let uploadWidth = 1170
    private let uploadHeight = 2532

    /// iPhone 15 Pro-ish feed container.
    private let containerWidth: CGFloat = 393
    private let screenScale: CGFloat = 3
    private var maxHeight: CGFloat { min(UIScreen.main.bounds.height * 0.58, 720) }

    func testPhoneScreenshotFidelityChainIdentifiesExactStage() throws {
        let uploadPNG = Self.makePNG(width: uploadWidth, height: uploadHeight)
        XCTAssertFalse(uploadPNG.isEmpty)

        // Stage: original upload
        let uploadPixels = try XCTUnwrap(ImageFidelityTrace.pixelSize(of: uploadPNG))
        XCTAssertEqual(uploadPixels.width, uploadWidth)
        XCTAssertEqual(uploadPixels.height, uploadHeight)

        // Stage: pipeline with feed request (maxPixelSize nil) — must not resize.
        let pipeline = DefaultImagePipeline(
            cache: InMemoryImageCache(),
            storage: FidelityStubStorage(),
            downloadService: FidelityStubDownload(data: uploadPNG)
        )

        let expectation = expectation(description: "pipeline")
        var downloaded = Data()
        Task {
            downloaded = try await pipeline.data(
                for: ImageRequest(
                    reference: MediaReference(
                        id: "phone-portrait.png",
                        kind: .image,
                        altText: nil
                    ),
                    purpose: .tradeScreenshot,
                    maxPixelSize: nil
                )
            )
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        let downloadedPixels = try XCTUnwrap(ImageFidelityTrace.pixelSize(of: downloaded))
        XCTAssertEqual(
            downloadedPixels,
            uploadPixels,
            "Fidelity break would be PIPELINE if download ≠ upload"
        )

        // Stage: decode the way AspectFitMediaView does today.
        let decoded = try XCTUnwrap(UIImage(data: downloaded, scale: screenScale))
        let decodedPixels = try XCTUnwrap(ImageFidelityTrace.pixelSize(of: decoded))
        XCTAssertEqual(decodedPixels, uploadPixels, "Decode must not resample pixels")
        XCTAssertEqual(decoded.scale, screenScale)
        XCTAssertEqual(decoded.size.width, CGFloat(uploadWidth) / screenScale, accuracy: 0.5)

        let reports = ImageFidelityTrace.probePipeline(
            label: "phone-screenshot",
            data: downloaded,
            url: "storage/object/public/screenshots/phone-portrait.png",
            httpStatus: 200,
            decodeScale: screenScale,
            containerWidthPoints: containerWidth,
            maxHeightPoints: maxHeight,
            screenScale: screenScale
        )

        let render = try XCTUnwrap(reports.first { $0.stage.contains("swiftui-render") })
        let displayPx = try XCTUnwrap(render.displayPixels)
        let fidelity = try XCTUnwrap(render.fidelityNote)

        // Expected display: tall portrait hits maxHeight before full width.
        let expected = ImageFidelityTrace.displaySize(
            imagePixel: uploadPixels,
            containerWidthPoints: containerWidth,
            maxHeightPoints: maxHeight,
            screenScale: screenScale
        )
        XCTAssertEqual(displayPx.width, expected.pixels.width)
        XCTAssertEqual(displayPx.height, expected.pixels.height)

        let needsUpscale =
            displayPx.width > uploadPixels.width || displayPx.height > uploadPixels.height

        // Print the chain for the deliverable (visible in test log).
        print(
            """
            [IMAGE FIDELITY CHAIN]
            Original upload:     \(uploadPixels.label)
            Downloaded:          \(downloadedPixels.label) (bytes=\(downloaded.count))
            Decoded UIImage:     \(decodedPixels.label) size=\(decoded.size) scale=\(decoded.scale)
            Displayed:           \(Int(expected.points.width))×\(Int(expected.points.height))pt → \(displayPx.label)
            Expected (1:1):      displayPx ≤ bitmap (\(uploadPixels.label))
            Web feed-thumb:      800px wide transform (quality 75) or original fallback
            Fidelity note:       \(fidelity)
            Upscale required?:   \(needsUpscale)
            """
        )

        XCTAssertFalse(
            needsUpscale,
            "If true, fidelity breaks at SWIFTUI RENDER (bitmap under-fills display pixels)"
        )
        XCTAssertTrue(
            fidelity.contains("Downscale") || fidelity.contains("1:1"),
            "Phone upload at \(uploadPixels.label) should not upscale on \(displayPx.label) display"
        )
    }

    func testFixtureUnsplashURLComparedToWebFeedThumb() async throws {
        // Same URL Profile/Feed fixtures use — public HTTPS, no auth.
        let url = URL(
            string: "https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200&q=80"
        )!
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode
        XCTAssertEqual(status, 200)
        let downloaded = try XCTUnwrap(ImageFidelityTrace.pixelSize(of: data))

        let reports = ImageFidelityTrace.probePipeline(
            label: "fixture-unsplash",
            data: data,
            url: url.absoluteString,
            httpStatus: status,
            decodeScale: screenScale,
            containerWidthPoints: containerWidth,
            maxHeightPoints: maxHeight,
            screenScale: screenScale
        )

        let render = try XCTUnwrap(reports.first { $0.stage.contains("swiftui-render") })
        let web = try XCTUnwrap(reports.first { $0.stage.contains("web-feed-thumb") })
        let displayPx = try XCTUnwrap(render.displayPixels)

        print(
            """
            [FIXTURE vs WEB]
            HTTP pixels:         \(downloaded.label) status=\(status ?? -1) bytes=\(data.count)
            Native display:      \(displayPx.label) — \(render.fidelityNote ?? "?")
            Web thumb equiv:     \(web.pixelSize?.label ?? "?") display \(web.displayPixels?.label ?? "?") — \(web.fidelityNote ?? "?")
            """
        )

        // Document: if fixture is ~1200 wide and display needs ~1179, native is ~1:1.
        // Web feed-thumb forces 800 wide → web would upscale more than native on 3×.
        if let webPx = web.pixelSize, let webDisplay = web.displayPixels {
            let nativeUpscale = Double(displayPx.width) / Double(downloaded.width)
            let webUpscale = Double(webDisplay.width) / Double(webPx.width)
            print(
                "[FIXTURE vs WEB] native width scale=\(String(format: "%.3f", nativeUpscale)) web width scale=\(String(format: "%.3f", webUpscale))"
            )
            if webUpscale > nativeUpscale + 0.05 {
                print(
                    "[FIXTURE vs WEB] ROOT CAUSE CANDIDATE: blur is NOT native downsampling — web feed-thumb (800px) is softer than native original on 3× screens. If the user still sees worse native quality, inspect LAYOUT (crop/letterbox), not decode."
                )
            }
        }
    }

    func testHistoricalPortraitDownsampleWouldUpscale() {
        // Documents the prior bug: longest-edge = screenWidth×scale under-fills portrait width.
        let needWidth = Int(containerWidth * screenScale) // 1179
        let wrongLongest = needWidth
        let wrongDecodedWidth = Int(Double(wrongLongest) * Double(uploadWidth) / Double(uploadHeight))
        XCTAssertLessThan(wrongDecodedWidth, needWidth)

        let display = ImageFidelityTrace.PixelSize(width: needWidth, height: 2000)
        let source = ImageFidelityTrace.PixelSize(width: wrongDecodedWidth, height: wrongLongest)
        let note = ImageFidelityTrace.compare(sourcePixels: source, displayPixels: display)
        XCTAssertTrue(note.contains("UPSCALE"), note)
        print("[HISTORICAL BUG] \(source.label) → display \(display.label): \(note)")
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

private struct FidelityStubStorage: ObjectStorageProviding {
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        path
    }

    func download(bucket: String, path: String) async throws -> Data { Data() }
    func delete(bucket: String, path: String) async throws {}
    func publicURL(bucket: String, path: String) -> URL? { nil }
}

private struct FidelityStubDownload: DownloadService {
    let data: Data
    func download(_ request: DownloadRequest) async throws -> Data { data }
}
