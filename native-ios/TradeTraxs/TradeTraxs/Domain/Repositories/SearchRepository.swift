import Foundation

nonisolated protocol SearchRepository: Sendable {
    func search(
        query: String,
        kinds: Set<SearchResultKind>,
        page: PageRequest
    ) async throws -> CursorPage<SearchResult>
}
