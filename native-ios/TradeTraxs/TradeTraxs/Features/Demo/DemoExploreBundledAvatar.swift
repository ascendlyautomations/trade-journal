import Foundation
import UIKit

/// Resolves bundled asset avatars for Explore fixtures (`bundle:AppLogo`).
nonisolated enum DemoExploreBundledAvatar {
    static let mediaIDPrefix = "bundle:"

    static func reference(assetName: String) -> MediaReference {
        MediaReference(
            id: "\(mediaIDPrefix)\(assetName)",
            kind: .image,
            altText: "TradeTraxs logo"
        )
    }

    static func uiImage(for reference: MediaReference) -> UIImage? {
        guard reference.id.hasPrefix(mediaIDPrefix) else { return nil }
        let assetName = String(reference.id.dropFirst(mediaIDPrefix.count))
        guard !assetName.isEmpty else { return nil }
        return UIImage(named: assetName)
    }
}
