import Foundation
import Observation

/// Hands a saved draft to the existing composer that is about to open.
@Observable
@MainActor
final class ContentDraftLaunchStore {
    static let shared = ContentDraftLaunchStore()

    private var pending: ContentDraft?

    private init() {}

    func stage(_ draft: ContentDraft) {
        pending = draft
    }

    func consume(expecting type: ContentDraftType) -> ContentDraft? {
        guard pending?.type == type else { return nil }
        defer { pending = nil }
        return pending
    }
}

/// Deletes a draft only after the matching upload job has created the real content.
@MainActor
final class ContentDraftPublicationCleanup {
    static let shared = ContentDraftPublicationCleanup()

    private var draftIDByJobID: [String: UUID] = [:]
    private var repository: (any ContentDraftRepository)?

    private init() {}

    func track(jobID: String, draftID: UUID, repository: any ContentDraftRepository) {
        draftIDByJobID = draftIDByJobID.filter { $0.value != draftID }
        draftIDByJobID[jobID] = draftID
        self.repository = repository
    }

    func noteJobCompleted(_ jobID: String) async {
        guard let draftID = draftIDByJobID[jobID], let repository else { return }
        do {
            try await repository.deleteDraft(id: draftID)
            draftIDByJobID.removeValue(forKey: jobID)
        } catch {
            // The published content already exists. Leave the mapping so a later
            // completion of this same job can retry, and leave the draft if it cannot.
        }
    }

    func resetForTesting() {
        draftIDByJobID = [:]
        repository = nil
    }
}
