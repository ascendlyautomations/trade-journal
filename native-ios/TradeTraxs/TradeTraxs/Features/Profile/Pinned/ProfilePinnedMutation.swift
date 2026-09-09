import Foundation

enum ProfilePinnedMutation {
    static func insert(
        request: ProfilePinRequest,
        preview: ProfilePinnedPreview,
        into current: [ProfilePinnedItem]
    ) -> [ProfilePinnedItem] {
        var items = current.filter {
            !($0.contentType == request.contentType && $0.contentID == request.contentID)
        }
        let position = request.replacePosition ?? nextAvailablePosition(in: items)
        if let replace = request.replacePosition {
            items.removeAll { $0.position == replace }
        }
        items.append(
            ProfilePinnedItem(
                contentType: request.contentType,
                contentID: request.contentID,
                position: position,
                preview: preview
            )
        )
        return normalizePositions(items)
    }

    static func remove(
        contentType: ProfilePinnedContentType,
        contentID: String,
        from current: [ProfilePinnedItem]
    ) -> [ProfilePinnedItem] {
        guard let removed = current.first(where: {
            $0.contentType == contentType && $0.contentID == contentID
        }) else { return current }
        var items = current.filter { $0.id != removed.id }
        for index in items.indices {
            if items[index].position > removed.position {
                items[index].position -= 1
            }
        }
        return normalizePositions(items)
    }

    static func swapPositions(
        from: Int,
        to: Int,
        in current: [ProfilePinnedItem]
    ) -> [ProfilePinnedItem] {
        var items = current
        guard let fromIndex = items.firstIndex(where: { $0.position == from }),
              let toIndex = items.firstIndex(where: { $0.position == to })
        else { return current }
        items[fromIndex].position = to
        items[toIndex].position = from
        return normalizePositions(items)
    }

    private static func nextAvailablePosition(in items: [ProfilePinnedItem]) -> Int {
        for position in 1...3 where !items.contains(where: { $0.position == position }) {
            return position
        }
        return min(items.count + 1, 3)
    }

    private static func normalizePositions(_ items: [ProfilePinnedItem]) -> [ProfilePinnedItem] {
        items.sorted { $0.position < $1.position }
    }
}
