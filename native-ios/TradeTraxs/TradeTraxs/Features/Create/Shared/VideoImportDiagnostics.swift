import Foundation

#if DEBUG
nonisolated enum VideoImportDiagnostics {
    static func log(_ message: String) {
        print("[VideoImport] \(message)")
    }

    static func logSelectionReceived(id: String) {
        log("selectionReceived id=\(id)")
    }

    static func logProviderLoadStarted(id: String) {
        log("providerLoadStarted id=\(id)")
    }

    static func logProviderLoadCompleted(id: String) {
        log("providerLoadCompleted id=\(id)")
    }

    static func logOwnedCopyStarted(id: String) {
        log("ownedCopyStarted id=\(id)")
    }

    static func logOwnedCopyCompleted(id: String, bytes: Int) {
        log("ownedCopyCompleted id=\(id) bytes=\(bytes)")
    }

    static func logProviderReleased(id: String) {
        log("providerReleased id=\(id)")
    }

    static func logImportFailed(id: String, stage: String, message: String) {
        log("failed id=\(id) stage=\(stage) message=\(message)")
    }

    static func logStaleImportDropped(id: String, generation: UInt64, current: UInt64) {
        log("staleImportDropped id=\(id) generation=\(generation) current=\(current)")
    }
}

nonisolated enum VideoPrepareDiagnostics {
    static func log(_ message: String) {
        print("[VideoPrepare] \(message)")
    }

    static func logStarted(id: String) {
        log("started id=\(id)")
    }

    static func logReusedExisting(id: String) {
        log("reusedExisting id=\(id)")
    }

    static func logCompleted(id: String, bytes: Int) {
        log("completed id=\(id) bytes=\(bytes)")
    }

    static func logFailed(id: String, stage: String, message: String) {
        log("failed id=\(id) stage=\(stage) message=\(message)")
    }

    static func logStalePrepareDropped(id: String, generation: UInt64, current: UInt64) {
        log("stalePrepareDropped id=\(id) generation=\(generation) current=\(current)")
    }
}
#else
nonisolated enum VideoImportDiagnostics {
    static func logSelectionReceived(id: String) {}
    static func logProviderLoadStarted(id: String) {}
    static func logProviderLoadCompleted(id: String) {}
    static func logOwnedCopyStarted(id: String) {}
    static func logOwnedCopyCompleted(id: String, bytes: Int) {}
    static func logProviderReleased(id: String) {}
    static func logImportFailed(id: String, stage: String, message: String) {}
    static func logStaleImportDropped(id: String, generation: UInt64, current: UInt64) {}
}

nonisolated enum VideoPrepareDiagnostics {
    static func logStarted(id: String) {}
    static func logReusedExisting(id: String) {}
    static func logCompleted(id: String, bytes: Int) {}
    static func logFailed(id: String, stage: String, message: String) {}
    static func logStalePrepareDropped(id: String, generation: UInt64, current: UInt64) {}
}
#endif
