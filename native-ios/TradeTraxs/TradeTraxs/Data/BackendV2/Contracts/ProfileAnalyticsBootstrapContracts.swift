import Foundation

// MARK: - Profile Analytics Bootstrap V2

nonisolated struct ProfileAnalyticsBootstrapMetaV2: Codable, Sendable, Equatable {
    var contract_version: String
    var server_time: String
    var viewer_id: String?
    var found: Bool
    var public_revision: PostgresFlexibleDouble?
    var public_updated_at: String?
}

nonisolated struct ProfileAnalyticsBootstrapV2: Codable, Sendable, Equatable {
    static let expectedContractVersion = "v2"

    var meta: ProfileAnalyticsBootstrapMetaV2
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var profile_id: String
        var modes: [String: JSONValue]
    }

    func validateContractVersion() throws {
        guard meta.contract_version == Self.expectedContractVersion else {
            throw BackendV2RPCError.contractVersionMismatch(
                expected: Self.expectedContractVersion,
                got: meta.contract_version
            )
        }
    }

    var publicRevisionInt: Int64? {
        guard meta.found else { return nil }
        return Int64(meta.public_revision?.value ?? 0)
    }
}

// MARK: - Profile public analytics revision

nonisolated struct ProfilePublicAnalyticsRevisionMetaV1: Codable, Sendable, Equatable {
    var contract_version: String
    var server_time: String
    var viewer_id: String?
    var found: Bool
}

nonisolated struct ProfilePublicAnalyticsRevisionV1: Codable, Sendable, Equatable {
    var meta: ProfilePublicAnalyticsRevisionMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var profile_id: String
        var revision: PostgresFlexibleDouble?
        var updated_at: String?
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }

    var revisionInt: Int64? {
        guard meta.found else { return nil }
        return Int64(data.revision?.value ?? 0)
    }
}
