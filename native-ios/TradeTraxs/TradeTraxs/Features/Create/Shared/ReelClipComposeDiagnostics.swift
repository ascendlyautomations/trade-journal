import Foundation

#if DEBUG
enum ClipComposeDiagnostics {
    static func logPosterFrameStarted(selectionID: String) {
        print("[ClipCompose] posterFrameStarted selectionID=\(selectionID)")
    }

    static func logPosterFrameReady(selectionID: String, elapsedMs: Double) {
        print(
            """
            [ClipCompose] posterFrameReady selectionID=\(selectionID) \
            elapsedMs=\(String(format: "%.0f", elapsedMs))
            """
        )
    }

    static func logComposerInteractive(selectionID: String, elapsedMs: Double) {
        print(
            """
            [ClipCompose] composerInteractive selectionID=\(selectionID) \
            elapsedMs=\(String(format: "%.0f", elapsedMs))
            """
        )
    }
}

enum ClipPrepareDiagnostics {
    static func logBackgroundStarted(selectionID: String, preparationTaskID: String) {
        print(
            """
            [ClipPrepare] backgroundStarted selectionID=\(selectionID) \
            preparationTaskID=\(preparationTaskID)
            """
        )
    }

    static func logBackgroundCompleted(
        selectionID: String,
        preparationTaskID: String,
        bytes: Int,
        elapsedMs: Double
    ) {
        print(
            """
            [ClipPrepare] backgroundCompleted selectionID=\(selectionID) \
            preparationTaskID=\(preparationTaskID) bytes=\(bytes) \
            elapsedMs=\(String(format: "%.0f", elapsedMs))
            """
        )
    }

    static func logBackgroundFailed(
        selectionID: String,
        preparationTaskID: String,
        reason: String
    ) {
        print(
            """
            [ClipPrepare] backgroundFailed selectionID=\(selectionID) \
            preparationTaskID=\(preparationTaskID) reason=\(reason)
            """
        )
    }
}

enum ClipPublishDiagnostics {
    static func logTapReceived(
        selectionID: String?,
        preparationState: String,
        publishID: String?
    ) {
        print(
            """
            [ClipPublish] tapReceived selectionID=\(selectionID ?? "none") \
            preparationState=\(preparationState) publishID=\(publishID ?? "pending")
            """
        )
    }

    static func logCommitted(
        publishID: String,
        selectionID: String,
        preparationTaskID: String?,
        queuedWhilePreparing: Bool
    ) {
        print(
            """
            [ClipPublish] committed publishID=\(publishID) selectionID=\(selectionID) \
            preparationTaskID=\(preparationTaskID ?? "none") \
            queuedWhilePreparing=\(queuedWhilePreparing)
            """
        )
    }

    static func logComposerDismissed(publishID: String) {
        print("[ClipPublish] composerDismissed publishID=\(publishID)")
    }

    static func logPreparationResolved(
        publishID: String,
        preparationTaskID: String,
        bytes: Int
    ) {
        print(
            """
            [ClipPublish] preparationResolved publishID=\(publishID) \
            preparationTaskID=\(preparationTaskID) bytes=\(bytes)
            """
        )
    }

    static func logPostingStarted(publishID: String) {
        print("[ClipPublish] postingStarted publishID=\(publishID)")
    }
}
#else
enum ClipComposeDiagnostics {
    static func logPosterFrameStarted(selectionID: String) {}
    static func logPosterFrameReady(selectionID: String, elapsedMs: Double) {}
    static func logComposerInteractive(selectionID: String, elapsedMs: Double) {}
}

enum ClipPrepareDiagnostics {
    static func logBackgroundStarted(selectionID: String, preparationTaskID: String) {}
    static func logBackgroundCompleted(
        selectionID: String,
        preparationTaskID: String,
        bytes: Int,
        elapsedMs: Double
    ) {}
    static func logBackgroundFailed(selectionID: String, preparationTaskID: String, reason: String) {}
}

enum ClipPublishDiagnostics {
    static func logTapReceived(selectionID: String?, preparationState: String, publishID: String?) {}
    static func logCommitted(
        publishID: String,
        selectionID: String,
        preparationTaskID: String?,
        queuedWhilePreparing: Bool
    ) {}
    static func logComposerDismissed(publishID: String) {}
    static func logPreparationResolved(publishID: String, preparationTaskID: String, bytes: Int) {}
    static func logPostingStarted(publishID: String) {}
}
#endif
