import Foundation

#if DEBUG
enum ClipFastOpenDiagnostics {
    static func logSelectionReceived(selectionID: String) {
        print("[ClipFastOpen] selectionReceived selectionID=\(selectionID)")
    }

    static func logComposerPresented(selectionID: String, elapsedMs: Double) {
        print(
            """
            [ClipFastOpen] composerPresented selectionID=\(selectionID) \
            elapsedMs=\(String(format: "%.0f", elapsedMs))
            """
        )
    }

    static func logLightweightPosterStarted(selectionID: String) {
        print("[ClipFastOpen] lightweightPosterStarted selectionID=\(selectionID)")
    }

    static func logLightweightPosterReady(selectionID: String, elapsedMs: Double) {
        print(
            """
            [ClipFastOpen] lightweightPosterReady selectionID=\(selectionID) \
            elapsedMs=\(String(format: "%.0f", elapsedMs))
            """
        )
    }

    static func logFullVideoImportStarted(selectionID: String) {
        print("[ClipFastOpen] fullVideoImportStarted selectionID=\(selectionID)")
    }

    static func logFullVideoImportCompleted(selectionID: String, elapsedMs: Double, bytes: Int) {
        print(
            """
            [ClipFastOpen] fullVideoImportCompleted selectionID=\(selectionID) \
            elapsedMs=\(String(format: "%.0f", elapsedMs)) bytes=\(bytes)
            """
        )
    }

    static func logPosterFallbackToOwnedCopy(selectionID: String, reason: String) {
        print(
            """
            [ClipFastOpen] posterFallbackToOwnedCopy selectionID=\(selectionID) \
            reason=\(reason)
            """
        )
    }
}
#else
enum ClipFastOpenDiagnostics {
    static func logSelectionReceived(selectionID: String) {}
    static func logComposerPresented(selectionID: String, elapsedMs: Double) {}
    static func logLightweightPosterStarted(selectionID: String) {}
    static func logLightweightPosterReady(selectionID: String, elapsedMs: Double) {}
    static func logFullVideoImportStarted(selectionID: String) {}
    static func logFullVideoImportCompleted(selectionID: String, elapsedMs: Double, bytes: Int) {}
    static func logPosterFallbackToOwnedCopy(selectionID: String, reason: String) {}
}
#endif
