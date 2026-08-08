import Foundation

nonisolated protocol SearchUsersUseCase: Sendable {
    func execute(query: String, page: PageRequest) async throws -> CursorPage<SearchResult>
}

nonisolated protocol SearchTradesUseCase: Sendable {
    func execute(query: String, page: PageRequest) async throws -> CursorPage<SearchResult>
}
