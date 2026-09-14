import Foundation
import OSLog

#if DEBUG
/// Row counts through Activity load/publish — DEBUG only.
nonisolated enum ActivityPipelineProbe {
    private static let logger = Logger(subsystem: AppLog.subsystem, category: "ActivityPipeline")

    static func record(
        stage: String,
        decoded: Int? = nil,
        stored: Int? = nil,
        grouped: Int? = nil,
        note: String? = nil
    ) {
        var parts = ["stage=\(stage)"]
        if let decoded { parts.append("decoded=\(decoded)") }
        if let stored { parts.append("stored=\(stored)") }
        if let grouped { parts.append("groupedRows=\(grouped)") }
        if let note, !note.isEmpty { parts.append("note=\(note)") }
        logger.debug("\(parts.joined(separator: " "), privacy: .public)")
    }
}
#else
nonisolated enum ActivityPipelineProbe {
    static func record(
        stage: String,
        decoded: Int? = nil,
        stored: Int? = nil,
        grouped: Int? = nil,
        note: String? = nil
    ) {}
}
#endif
