import Foundation
import OSLog

/// PostgREST PATCH + fresh SELECT audit for live personal drawdown columns on `accounts`.
nonisolated enum LivePersonalDrawdownPersistenceAudit {
    struct ColumnSnapshot: Sendable, Equatable {
        var maxDrawdown: Decimal?
        var drawdownType: String?
        var floorCap: Decimal?
        var mode: String?
        var category: String?

        static func from(_ row: TradeDTO.Account) -> ColumnSnapshot {
            ColumnSnapshot(
                maxDrawdown: DecimalParser.parseFlexible(row.max_drawdown),
                drawdownType: row.drawdown_type,
                floorCap: DecimalParser.parseFlexible(row.drawdown_floor_cap),
                mode: row.mode,
                category: row.category ?? row.account_type
            )
        }
    }

    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "LivePersonalDrawdown"
    )

    static func logSavePipeline(
        accountID: TradingAccountID,
        ownerID: ProfileID,
        config: LivePersonalDrawdownConfig?,
        patchBody: LivePersonalDrawdownAccountPatchBody,
        beforeSelect: ColumnSnapshot,
        updateRowCount: Int,
        patchResponse: ColumnSnapshot,
        verifySelect: ColumnSnapshot
    ) {
        let intendedMax = config.map { NSDecimalNumber(decimal: $0.limitAmount).stringValue }
        let intendedType = config.map { LivePersonalDrawdownEngine.wireDrawdownTypeRaw(for: $0.limitType) }

        logger.info(
            """
            liveDrawdown.save account=\(accountID.rawValue, privacy: .public) owner=\(ownerID.rawValue, privacy: .public) \
            mode=\(beforeSelect.mode ?? "?", privacy: .public) category=\(beforeSelect.category ?? "?", privacy: .public) \
            dbBefore max=\(format(beforeSelect.maxDrawdown), privacy: .public) type=\(beforeSelect.drawdownType ?? "null", privacy: .public) cap=\(format(beforeSelect.floorCap), privacy: .public) \
            patch max=\(patchBody.max_drawdown.map { String($0) } ?? "null", privacy: .public) type=\(patchBody.drawdown_type ?? "null", privacy: .public) cap=\(patchBody.drawdown_floor_cap.map { String($0) } ?? "null", privacy: .public) \
            intended max=\(intendedMax ?? "null", privacy: .public) type=\(intendedType ?? "null", privacy: .public) \
            rows=\(updateRowCount, privacy: .public) \
            patchResponse max=\(format(patchResponse.maxDrawdown), privacy: .public) type=\(patchResponse.drawdownType ?? "null", privacy: .public) \
            verifySelect max=\(format(verifySelect.maxDrawdown), privacy: .public) type=\(verifySelect.drawdownType ?? "null", privacy: .public) cap=\(format(verifySelect.floorCap), privacy: .public)
            """
        )

        if !snapshotsMatch(patchResponse, verifySelect) {
            logger.error(
                "liveDrawdown.save MISMATCH patch-vs-select account=\(accountID.rawValue, privacy: .public)"
            )
        }
        if let config, config.limitAmount > 0 {
            let verifyLimit = verifySelect.maxDrawdown
            if verifyLimit == nil || verifyLimit! <= 0 {
                logger.error(
                    "liveDrawdown.save MISSING persisted limit account=\(accountID.rawValue, privacy: .public)"
                )
            }
        }
    }

    static func logBootstrapAccountWire(
        accountID: String,
        wire: ColumnSnapshot,
        mappedLimit: Decimal?,
        mappedType: LivePersonalDrawdownType?
    ) {
        logger.debug(
            """
            liveDrawdown.bootstrapWire account=\(accountID, privacy: .public) \
            wire max=\(format(wire.maxDrawdown), privacy: .public) type=\(wire.drawdownType ?? "null", privacy: .public) \
            mapped limit=\(format(mappedLimit), privacy: .public) type=\(mappedType.map { String(describing: $0) } ?? "nil", privacy: .public)
            """
        )
    }

    private static func format(_ value: Decimal?) -> String {
        guard let value else { return "null" }
        return NSDecimalNumber(decimal: value).stringValue
    }

    private static func snapshotsMatch(_ lhs: ColumnSnapshot, _ rhs: ColumnSnapshot) -> Bool {
        lhs.drawdownType == rhs.drawdownType
            && numericMatch(lhs.maxDrawdown, rhs.maxDrawdown)
            && numericMatch(lhs.floorCap, rhs.floorCap)
    }

    private static func numericMatch(_ lhs: Decimal?, _ rhs: Decimal?, tolerance: Decimal = 0.0001) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (l?, r?):
            return abs(l - r) <= tolerance
        default:
            return false
        }
    }
}