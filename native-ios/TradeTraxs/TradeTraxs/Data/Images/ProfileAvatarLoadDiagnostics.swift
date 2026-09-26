#if DEBUG
import Foundation

/// DEBUG verification for profile avatar cache-first list loading (Activity, etc.).
enum ProfileAvatarLoadDiagnostics {
    enum Source: String {
        case displayMemory
        case pipelineMemory
        case pipelineDisk
        case network
    }

    static func log(surface: String, profileID: String, cacheKey: String, source: Source) {
        print(
            "[ProfileAvatarLoad] surface=\(surface) profile=\(profileID) key=\(cacheKey.suffix(48)) source=\(source.rawValue)"
        )
    }
}
#endif
