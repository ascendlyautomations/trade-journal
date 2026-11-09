import Foundation
import SwiftUI

nonisolated enum ConversationSharedMediaSupport {
    static let pageSize = 12
}

/// Uniform 3-column square thumbnail grid (profile browse parity).
/// Drives ``View/sheet(item:)`` so the gallery view always mounts with a view model (avoids empty first presentation).
@MainActor
struct ConversationSharedMediaSheetPresentation: Identifiable {
    let id = UUID()
    let viewModel: ConversationSharedMediaViewModel
}

nonisolated enum ConversationSharedMediaGalleryLayout {
    static let columnCount = 3
    static let interItemSpacing: CGFloat = 2

    static var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: interItemSpacing),
            count: columnCount
        )
    }
}

nonisolated struct ConversationSharedMediaCursor: Equatable, Sendable {
    var createdAt: String
    var id: MessageID
}

nonisolated struct ConversationSharedMediaItem: Identifiable, Equatable, Sendable {
    var id: MessageID
    var senderID: ProfileID?
    var imageURL: String
    var createdAt: String

    var mediaReference: MediaReference {
        MediaReference(id: imageURL, kind: .image, altText: nil)
    }
}

nonisolated enum ConversationSharedMediaFetchResult: Sendable {
    case success([ConversationSharedMediaItem])
    case failure(String)
}

nonisolated enum ConversationSharedMediaPagination {
    static func merged(
        existing: [ConversationSharedMediaItem],
        page: [ConversationSharedMediaItem]
    ) -> [ConversationSharedMediaItem] {
        var seen = Set(existing.map(\.id))
        var output = existing
        for item in page where !seen.contains(item.id) {
            seen.insert(item.id)
            output.append(item)
        }
        return output
    }

    static func nextCursor(from items: [ConversationSharedMediaItem]) -> ConversationSharedMediaCursor? {
        guard let last = items.last else { return nil }
        return ConversationSharedMediaCursor(createdAt: last.createdAt, id: last.id)
    }
}
