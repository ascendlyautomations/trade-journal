import Foundation

/// Data-layer configuration derived from ``AppConfiguration``.
nonisolated struct DataConfiguration: Sendable, Equatable {
    var enablesDiskCache: Bool
    var enablesMemoryCache: Bool
    var enablesRealtime: Bool
    var enablesImagePipeline: Bool

    static let `default` = DataConfiguration(
        enablesDiskCache: true,
        enablesMemoryCache: true,
        enablesRealtime: false,
        enablesImagePipeline: true
    )

    static func make(for appConfiguration: AppConfiguration) -> DataConfiguration {
        _ = appConfiguration
        return DataConfiguration(
            enablesDiskCache: true,
            enablesMemoryCache: true,
            // Hub is wired; connection starts via ``RealtimeHub.start()`` when Auth UI /
            // session lifecycle requests it. Avoid auto-connect on cold launch.
            enablesRealtime: false,
            enablesImagePipeline: true
        )
    }
}

/// Marker documenting Data layer invariants.
enum DataLayer {
    static let moduleName = "Data"
}
