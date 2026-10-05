import Foundation

/// Owner-only composer drafts. Not part of feed, profile, trade, or analytics reads.
nonisolated protocol ContentDraftRepository: Sendable {
    func listDrafts() async throws -> [ContentDraft]
    func saveDraft(_ draft: ContentDraft) async throws -> ContentDraft
    func deleteDraft(id: UUID) async throws
    func uploadDraftImage(draftID: UUID, data: Data) async throws -> String
    func uploadDraftVideo(draftID: UUID, fileURL: URL, contentType: String) async throws -> String
    func deleteDraftMedia(paths: [String]) async
}
