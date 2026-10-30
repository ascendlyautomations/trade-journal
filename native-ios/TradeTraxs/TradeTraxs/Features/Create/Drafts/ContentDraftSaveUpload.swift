import Foundation

/// Routes composer draft saves through ``GlobalUploadCoordinator`` (same upload % bar as publish).
@MainActor
enum ContentDraftSaveUpload {
    static func start(
        jobTitle: String = "Draft",
        operation: @escaping @MainActor (_ jobID: String) async throws -> Void,
        onEnqueued: @escaping @MainActor () -> Void = {},
        onFailure: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        _ = GlobalUploadCoordinator.shared.enqueueContentDraftSave(
            title: jobTitle,
            operation: operation,
            onSuccess: {
                SaveSuccessConfirmationCenter.shared.present("Draft saved")
            },
            onFailure: onFailure
        )
        onEnqueued()
    }

    static func noteSavingRecord(jobID: String) {
        GlobalUploadCoordinator.shared.noteContentDraftSavingRecord(jobID: jobID)
    }
}
