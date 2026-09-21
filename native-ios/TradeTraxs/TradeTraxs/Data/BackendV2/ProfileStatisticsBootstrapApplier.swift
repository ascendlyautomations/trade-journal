import Foundation

nonisolated enum ProfileStatisticsBootstrapApplier {
    struct Applied: Sendable {
        var modeResults: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result]
    }

    nonisolated static func apply(_ bootstrap: ProfileStatisticsBootstrapV1) -> Applied {
        Applied(modeResults: ProfileStatisticsBootstrapModeMapping.mapModes(bootstrap.data.modes))
    }
}
