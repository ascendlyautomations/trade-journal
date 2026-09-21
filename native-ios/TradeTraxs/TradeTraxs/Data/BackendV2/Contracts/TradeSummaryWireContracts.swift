import Foundation

/// Phase 8B — canonical TradeSummary wire (`summary_schema = trade_summary_v1`).
nonisolated struct TradeSummaryWireV1: Codable, Sendable, Equatable {
    static let schema = "trade_summary_v1"

    var summary_schema: String
    var id: String
    var user_id: String
    var ticker: String?
    var direction: String?
    var pnl: PostgresFlexibleDouble?
    var rr: PostgresFlexibleDouble?
    var points: PostgresFlexibleDouble?
    var contracts: PostgresFlexibleDouble?
    var entry_time: String?
    var exit_time: String?
    var created_at: String
    var is_public: PostgresFlexibleBool?
    var public_description: String?
    var note_preview: String?
    var image_url: String?
    var image_crop: JSONValue?
    var image_display_mode: String?
    var mode: String?
    var account_type: String?
    var trade_mode: String?
    var duration_seconds: PostgresFlexibleDouble?
    var duration_text: String?

    func validateSchema() throws {
        guard summary_schema == Self.schema else {
            throw BackendV2RPCError.contractVersionMismatch(
                expected: Self.schema,
                got: summary_schema
            )
        }
    }
}

/// Phase 8D — owner Journal list row (`trade_summary_v1` + owner extension keys).
nonisolated struct TradeOwnerJournalSummaryWireV1: Codable, Sendable, Equatable {
    var summary_schema: String
    var id: String
    var user_id: String
    var ticker: String?
    var direction: String?
    var pnl: PostgresFlexibleDouble?
    var rr: PostgresFlexibleDouble?
    var points: PostgresFlexibleDouble?
    var contracts: PostgresFlexibleDouble?
    var entry_time: String?
    var exit_time: String?
    var created_at: String
    var is_public: PostgresFlexibleBool?
    var public_description: String?
    var note_preview: String?
    var image_url: String?
    var image_crop: JSONValue?
    var image_display_mode: String?
    var mode: String?
    var account_type: String?
    var trade_mode: String?
    var duration_seconds: PostgresFlexibleDouble?
    var duration_text: String?
    var account_id: String?
    var account_name: String?
    var strategy: String?
    var entry_price: PostgresFlexibleDouble?
    var exit_price: PostgresFlexibleDouble?
    var session: String?

    func validateSchema() throws {
        guard summary_schema == TradeSummaryWireV1.schema else {
            throw BackendV2RPCError.contractVersionMismatch(
                expected: TradeSummaryWireV1.schema,
                got: summary_schema
            )
        }
    }
}

/// Trades list bootstrap — V2 envelope (`contract_version = v2`, TradeSummary rows).
nonisolated struct TradesListBootstrapV2: Codable, Sendable, Equatable {
    var meta: Meta
    var data: DataPayload

    nonisolated struct Meta: Codable, Sendable, Equatable {
        var contract_version: String
        var server_time: String
        var viewer_id: String?
    }

    nonisolated struct PageMeta: Codable, Sendable, Equatable {
        var limit: Int
        var returned: Int
        var has_more: Bool
    }

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var accounts: [DashboardAccountWireV1]
        var trades: [TradeOwnerJournalSummaryWireV1]
        var next_cursor: String?
        var page_meta: PageMeta
    }

    func validateContractVersion() throws {
        guard meta.contract_version == "v2" else {
            throw BackendV2RPCError.contractVersionMismatch(
                expected: "v2",
                got: meta.contract_version
            )
        }
    }
}

/// Profile tab trades bootstrap — V2 envelope (`contract_version = v2`).
nonisolated struct ProfileTabBootstrapV2: Codable, Sendable, Equatable {
    var meta: ProfileTabBootstrapMetaV2
    var data: DataPayload

    nonisolated struct ProfileTabBootstrapMetaV2: Codable, Sendable, Equatable {
        var contract_version: String
        var found: Bool
        var server_time: String?
        var viewer_id: String?
    }

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var tab: String
        var items: [TradeSummaryWireV1]
        var engagement: [String: ProfileBootstrapV1.TradeEngagementWire]?
        var next_cursor: String?
    }

    func validateContractVersion() throws {
        guard meta.contract_version == "v2" else {
            throw BackendV2RPCError.contractVersionMismatch(
                expected: "v2",
                got: meta.contract_version
            )
        }
    }
}
