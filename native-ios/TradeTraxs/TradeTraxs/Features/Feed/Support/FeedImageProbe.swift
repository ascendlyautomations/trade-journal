import CoreGraphics
import Foundation

#if DEBUG
enum FeedImageProbe {
    enum Event: String {
        case mount
        case requestStarted
        case cacheHitMemory
        case cacheHitDisk
        case networkStarted
        case imageDecoded
        case imageAssigned
        case layoutSubviews
        case staleCompletionDropped
    }

    static func log(
        id: String,
        event: Event,
        url: String? = nil,
        rootBounds: CGRect? = nil,
        imageBounds: CGRect? = nil,
        pixels: CGSize? = nil,
        mainThread: Bool? = nil
    ) {
        var parts = ["[FeedImage] id=\(id) event=\(event.rawValue)"]
        if let url, !url.isEmpty {
            parts.append("url=\(url)")
        }
        if let rootBounds {
            parts.append("rootBounds=\(describe(rootBounds))")
        }
        if let imageBounds {
            parts.append("imageBounds=\(describe(imageBounds))")
        }
        if let pixels {
            parts.append("pixels=\(Int(pixels.width))x\(Int(pixels.height))")
        }
        if let mainThread {
            parts.append("mainThread=\(mainThread)")
        }
        print(parts.joined(separator: " "))
    }

    private static func describe(_ rect: CGRect) -> String {
        "(\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width))x\(Int(rect.height)))"
    }
}
#else
enum FeedImageProbe {
    enum Event: String {
        case mount, requestStarted, cacheHitMemory, cacheHitDisk, networkStarted
        case imageDecoded, imageAssigned, layoutSubviews, staleCompletionDropped
    }

    static func log(
        id: String,
        event: Event,
        url: String? = nil,
        rootBounds: CGRect? = nil,
        imageBounds: CGRect? = nil,
        pixels: CGSize? = nil,
        mainThread: Bool? = nil
    ) {}
}
#endif
