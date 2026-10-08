import UIKit

/// Process-lifetime decoded images for Feed rows — survives ``LazyVStack`` teardown when scrolling back upward.
@MainActor
enum FeedDisplayImageSessionCache {
    private static var images: [String: UIImage] = [:]
    private static var aspects: [String: CGFloat] = [:]
    private static var order: [String] = []
    private static let maxEntries = 64

    static func uiImage(forEntryID id: String) -> UIImage? {
        images[id]
    }

    static func aspectRatio(forEntryID id: String) -> CGFloat? {
        aspects[id]
    }

    static func store(image: UIImage, forEntryID id: String) {
        guard !id.isEmpty else { return }
        let aspect = MediaImageOrientation.visualAspectRatio(of: image)
        if images[id] != nil {
            images[id] = image
            aspects[id] = aspect
            touch(id)
            return
        }
        while order.count >= maxEntries, let oldest = order.first {
            order.removeFirst()
            images.removeValue(forKey: oldest)
            aspects.removeValue(forKey: oldest)
        }
        images[id] = image
        aspects[id] = aspect
        order.append(id)
    }

    static func resetForTesting() {
        images = [:]
        aspects = [:]
        order = []
    }

    private static func touch(_ id: String) {
        order.removeAll { $0 == id }
        order.append(id)
    }
}
