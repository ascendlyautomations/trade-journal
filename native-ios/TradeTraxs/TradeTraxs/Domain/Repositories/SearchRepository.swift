import Foundation

nonisolated protocol SearchRepository: Sendable {
    func search(
        query: String,
        kinds: Set<SearchResultKind>,
        page: PageRequest,
        excludingProfileID: ProfileID?
    ) async throws -> CursorPage<SearchResult>
}

extension SearchRepository {
    func search(
        query: String,
        kinds: Set<SearchResultKind>,
        page: PageRequest
    ) async throws -> CursorPage<SearchResult> {
        try await search(
            query: query,
            kinds: kinds,
            page: page,
            excludingProfileID: nil
        )
    }
}
