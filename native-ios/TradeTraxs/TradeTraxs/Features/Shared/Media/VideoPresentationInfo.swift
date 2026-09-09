import AVFoundation
import CoreGraphics
import SwiftUI

enum VideoOrientationClass: String, Equatable, Sendable {
    case portrait
    case square
    case landscape
}

enum VideoPresentationSurface: String, Sendable {
    case clipsPager
    case feedInline
    case profileThumbnail
}

/// Authoritative oriented video dimensions — applies `preferredTransform` before classification.
struct VideoPresentationInfo: Equatable, Sendable {
    let rawSize: CGSize
    let preferredTransform: CGAffineTransform
    let orientedSize: CGSize
    let aspectRatio: CGFloat
    let orientation: VideoOrientationClass

    static func from(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> VideoPresentationInfo {
        let transformed = naturalSize.applying(preferredTransform)
        let oriented = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        let aspect = oriented.width / max(oriented.height, 1)
        let orientation: VideoOrientationClass
        if abs(aspect - 1) <= 0.08 {
            orientation = .square
        } else if aspect < 1 {
            orientation = .portrait
        } else {
            orientation = .landscape
        }
        return VideoPresentationInfo(
            rawSize: naturalSize,
            preferredTransform: preferredTransform,
            orientedSize: oriented,
            aspectRatio: aspect,
            orientation: orientation
        )
    }

    static func load(asset: AVAsset) async -> VideoPresentationInfo? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        guard let naturalSize = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform)
        else { return nil }
        return from(naturalSize: naturalSize, preferredTransform: transform)
    }

    static func load(url: URL) async -> VideoPresentationInfo? {
        await load(asset: AVURLAsset(url: url))
    }

    func playerGravity(for surface: VideoPresentationSurface) -> AVLayerVideoGravity {
        switch surface {
        case .feedInline:
            return .resizeAspect
        case .clipsPager:
            switch orientation {
            case .portrait:
                return .resizeAspectFill
            case .square, .landscape:
                return .resizeAspect
            }
        case .profileThumbnail:
            return .resizeAspectFill
        }
    }

    func swiftUIPosterContentMode(for surface: VideoPresentationSurface) -> ContentMode {
        switch surface {
        case .feedInline:
            return .fit
        case .clipsPager:
            return orientation == .portrait ? .fill : .fit
        case .profileThumbnail:
            return .fill
        }
    }

    /// Container width / height for inline surfaces.
    func containerAspectRatio(for surface: VideoPresentationSurface) -> CGFloat {
        switch surface {
        case .feedInline:
            return aspectRatio
        case .clipsPager:
            return aspectRatio
        case .profileThumbnail:
            return 1
        }
    }

    /// Inline Feed — compact capped media region; video aspect-fits inside (never cropped).
    func feedInlineContainerSize(containerWidth: CGFloat) -> CGSize {
        FeedInlineClipLayout.containerSize(
            containerWidth: containerWidth,
            videoAspectRatio: aspectRatio
        )
    }

    func gravityLabel(for surface: VideoPresentationSurface) -> String {
        playerGravity(for: surface) == .resizeAspectFill ? "aspectFill" : "aspectFit"
    }
}

#if DEBUG
enum VideoPresentationProbe {
    static func log(
        surface: VideoPresentationSurface,
        info: VideoPresentationInfo,
        containerAspect: CGFloat? = nil
    ) {
        let containerText: String
        if let containerAspect {
            containerText = String(format: "%.4f", containerAspect)
        } else {
            containerText = "n/a"
        }
        print(
            "[VideoPresentation] surface=\(surface.rawValue) "
                + "rawSize=\(Int(info.rawSize.width))x\(Int(info.rawSize.height)) "
                + "preferredTransform=[\(transformSummary(info.preferredTransform))] "
                + "orientedSize=\(Int(info.orientedSize.width))x\(Int(info.orientedSize.height)) "
                + "aspectRatio=\(String(format: "%.4f", info.aspectRatio)) "
                + "classification=\(info.orientation.rawValue) "
                + "gravity=\(info.gravityLabel(for: surface)) "
                + "containerAspect=\(containerText)"
        )
    }

    private static func transformSummary(_ transform: CGAffineTransform) -> String {
        String(
            format: "a=%.2f,b=%.2f,c=%.2f,d=%.2f,tx=%.0f,ty=%.0f",
            transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty
        )
    }
}
#else
enum VideoPresentationProbe {
    static func log(
        surface: VideoPresentationSurface,
        info: VideoPresentationInfo,
        containerAspect: CGFloat? = nil
    ) {}
}
#endif
