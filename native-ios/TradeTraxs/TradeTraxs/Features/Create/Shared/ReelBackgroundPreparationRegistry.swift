import Foundation

/// Single background `MediaVideoPreparation` task per Clip selection — shared by composer and upload job.
actor ReelBackgroundPreparationRegistry {
    static let shared = ReelBackgroundPreparationRegistry()

    struct PreparedPackage: Sendable {
        var prepared: MediaVideoPreparation.PreparedLocalVideo
        var ownedSourceURL: URL
        var selectionID: String
    }

    private struct Entry {
        var selectionID: String
        var ownedSourceURL: URL
        var adoptedForUpload: Bool
        var result: Result<PreparedPackage, Error>?
        var task: Task<PreparedPackage, Error>?
    }

    private var entries: [String: Entry] = [:]

    func startIfNeeded(
        preparationTaskID: String,
        selectionID: String,
        ownedSourceURL: URL,
        contentType: String
    ) {
        guard entries[preparationTaskID] == nil else { return }
        let task = Task {
            try Task.checkCancellation()
            let prepared = try await ReelEncodingPipeline.prepareForUpload(
                from: ownedSourceURL,
                contentType: contentType,
                onProgress: nil
            )
            return PreparedPackage(
                prepared: prepared,
                ownedSourceURL: ownedSourceURL,
                selectionID: selectionID
            )
        }
        entries[preparationTaskID] = Entry(
            selectionID: selectionID,
            ownedSourceURL: ownedSourceURL,
            adoptedForUpload: false,
            result: nil,
            task: task
        )
        Task {
            await self.completeTask(preparationTaskID: preparationTaskID, task: task)
        }
    }

    private func completeTask(preparationTaskID: String, task: Task<PreparedPackage, Error>) async {
        do {
            let package = try await task.value
            storeResult(preparationTaskID: preparationTaskID, .success(package))
        } catch {
            storeResult(preparationTaskID: preparationTaskID, .failure(error))
        }
    }

    private func storeResult(preparationTaskID: String, _ result: Result<PreparedPackage, Error>) {
        guard var entry = entries[preparationTaskID] else { return }
        entry.result = result
        entry.task = nil
        entries[preparationTaskID] = entry
    }

    func adoptForUpload(preparationTaskID: String) {
        guard var entry = entries[preparationTaskID] else { return }
        entry.adoptedForUpload = true
        entries[preparationTaskID] = entry
    }

    func isAdoptedForUpload(preparationTaskID: String) -> Bool {
        entries[preparationTaskID]?.adoptedForUpload ?? false
    }

    func awaitPrepared(preparationTaskID: String) async throws -> PreparedPackage {
        if let result = entries[preparationTaskID]?.result {
            return try result.get()
        }
        guard let task = entries[preparationTaskID]?.task else {
            throw AppError.unknown(message: "Prepared video is no longer available.")
        }
        let package = try await task.value
        storeResult(preparationTaskID: preparationTaskID, .success(package))
        return package
    }

    func cancel(preparationTaskID: String) {
        guard let entry = entries[preparationTaskID], !entry.adoptedForUpload else { return }
        entry.task?.cancel()
        if case .success(let package) = entry.result {
            MediaVideoPreparation.cleanupTemporaryFile(at: package.prepared.fileURL)
        }
        let ownedSourceURL = entry.ownedSourceURL
        entries.removeValue(forKey: preparationTaskID)
        ReelVideoImport.cleanup(url: ownedSourceURL)
    }

    func releaseAfterUpload(preparationTaskID: String) {
        entries.removeValue(forKey: preparationTaskID)
    }
}
