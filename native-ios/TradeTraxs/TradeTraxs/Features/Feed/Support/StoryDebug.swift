import Foundation
import OSLog

/// Targeted story viewer / archive instrumentation (`[StoryDebug]` in Xcode console).
nonisolated enum StoryDebug {
    private static let logger = Logger(subsystem: AppLog.subsystem, category: "StoryDebug")

    static func log(_ stage: String, _ detail: String) {
        #if DEBUG
        let redacted = StorySignedURLSupport.redactForLog(detail)
        let line = "[StoryDebug] \(stage): \(redacted)"
        print(line)
        logger.debug("\(stage, privacy: .public) \(redacted, privacy: .public)")
        #endif
    }

    static func logMediaRef(_ stage: String, storyID: String?, mediaID: String, kind: String) {
        let idTail = String(StorySignedURLSupport.redactForLog(mediaID).prefix(96))
        let scheme: String = {
            let lower = mediaID.lowercased()
            if lower.hasPrefix("https://") { return "https" }
            if lower.hasPrefix("http://") { return "http" }
            return "path"
        }()
        log(stage, "story=\(storyID ?? "?") mediaKind=\(kind) refScheme=\(scheme) ref=\(idTail)")
    }
}