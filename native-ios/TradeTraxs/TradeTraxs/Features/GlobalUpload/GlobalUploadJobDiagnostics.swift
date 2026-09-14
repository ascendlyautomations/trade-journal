import Foundation

#if DEBUG
/// Temporary tracing for global upload lifetime / cancellation (P0).
enum GlobalUploadJobDiagnostics {
    enum Event: String {
        case enqueued
        case started
        case composerDismissed
        case storageCompleted
        case publishStarted
        case publishCompleted
        case completed
        case removed
        case staleRunIgnored
        case cancelled
        case failed
    }

    static func log(
        id: String,
        kind: UploadJobKind,
        event: Event,
        taskCancelled: Bool,
        generation: UInt64? = nil,
        cancelSource: String? = nil,
        detail: String? = nil,
        removalReason: String? = nil
    ) {
        var line =
            "[GLOBAL_UPLOAD_JOB] id=\(id) kind=\(kind.rawValue) event=\(event.rawValue) taskCancelled=\(taskCancelled)"
        if let generation {
            line += " generation=\(generation)"
        }
        if let cancelSource, !cancelSource.isEmpty {
            line += " cancelSource=\(cancelSource)"
        }
        if let detail, !detail.isEmpty {
            line += " detail=\(detail)"
        }
        if event == .removed, let removalReason, !removalReason.isEmpty {
            line += " reason=\(removalReason)"
        }
        print(line)
    }

    static func logPublishRequest(jobID: String, kind: UploadJobKind, owner: String) {
        print(
            """
            [PUBLISH_REQUEST] jobID=\(jobID) kind=\(kind.rawValue) \
            taskCancelled=\(Task.isCancelled) owner=\(owner)
            """
        )
    }
}
#else
enum GlobalUploadJobDiagnostics {
    enum Event: String {
        case enqueued
        case started
        case composerDismissed
        case storageCompleted
        case publishStarted
        case publishCompleted
        case completed
        case removed
        case staleRunIgnored
        case cancelled
        case failed
    }

    static func log(
        id: String,
        kind: UploadJobKind,
        event: Event,
        taskCancelled: Bool,
        generation: UInt64? = nil,
        cancelSource: String? = nil,
        detail: String? = nil,
        removalReason: String? = nil
    ) {}

    static func logPublishRequest(jobID: String, kind: UploadJobKind, owner: String) {}
}
#endif
