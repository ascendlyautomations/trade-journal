import Foundation

/// Web `CsvFileFormat` — detection order: tradovate → tradezella → entered_exited → flexible.
nonisolated enum CSVFileFormat: String, Hashable, Codable, Sendable, CaseIterable {
    case tradovate
    case tradezella
    case enteredExited = "entered_exited"
    case flexible

    var displayName: String {
        switch self {
        case .tradovate: return "Tradovate"
        case .tradezella: return "TradeZella"
        case .enteredExited: return "Entered/Exited"
        case .flexible: return "Generic CSV"
        }
    }
}

/// Web `LogicalField` — columns that can be mapped for flexible CSVs.
nonisolated enum CSVLogicalField: String, Hashable, Codable, Sendable, CaseIterable, Identifiable {
    case date
    case symbol
    case direction
    case entryPrice = "entry_price"
    case exitPrice = "exit_price"
    case pnl
    case contracts
    case points
    case rr
    case session
    case accountName = "account_name"
    case accountID = "account_id"
    case accountSize = "account_size"
    case strategy
    case commission
    case fees
    case swap
    case notes
    case entryTime
    case exitTime
    case duration

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .date: return "Date"
        case .symbol: return "Symbol"
        case .direction: return "Direction"
        case .entryPrice: return "Entry Price"
        case .exitPrice: return "Exit Price"
        case .pnl: return "P&L"
        case .contracts: return "Contracts"
        case .points: return "Points"
        case .rr: return "R:R"
        case .session: return "Session"
        case .accountName: return "Account Name"
        case .accountID: return "Account ID"
        case .accountSize: return "Account Size"
        case .strategy: return "Strategy"
        case .commission: return "Commission"
        case .fees: return "Fees"
        case .swap: return "Swap"
        case .notes: return "Notes"
        case .entryTime: return "Entry Time"
        case .exitTime: return "Exit Time"
        case .duration: return "Duration"
        }
    }

    /// Fields required for a successful flexible-row parse (web `buildFlexibleTradeInsert`).
    static var requiredForFlexibleImport: [CSVLogicalField] {
        [.date, .symbol, .direction, .pnl]
    }
}

/// Normalized trade ready for review / bulk insert — mirrors web `CsvTradeInsert`.
nonisolated struct CSVParsedTrade: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var rowNumber: Int
    var symbol: String
    var side: TradeSide
    var quantity: Decimal
    var entryPrice: Decimal?
    var exitPrice: Decimal?
    var entryAt: Date
    var exitAt: Date?
    var realizedPnL: Decimal
    var riskReward: Decimal?
    var points: Decimal?
    var sessionLabel: String?
    var notes: String
    var strategy: String?
    var csvAccountName: String?
    var csvAccountID: String?
    var csvAccountSize: String?
    var durationSeconds: Int?
    var status: CSVTradeParseStatus
    var warningMessages: [String]

    var isImportable: Bool {
        status == .ready || status == .needsReview
    }
}

nonisolated enum CSVTradeParseStatus: String, Hashable, Codable, Sendable {
    case ready
    case needsReview
    case invalid
}

nonisolated struct CSVParseRowFailure: Hashable, Codable, Sendable, Identifiable {
    var id: Int { rowNumber }
    var rowNumber: Int
    var reason: String
}

nonisolated struct CSVParseSummary: Hashable, Codable, Sendable {
    var format: CSVFileFormat
    var fileName: String
    var totalRows: Int
    var successCount: Int
    var failedCount: Int
    var headers: [String]
    var trades: [CSVParsedTrade]
    var failures: [CSVParseRowFailure]

    var readyCount: Int { trades.filter { $0.status == .ready }.count }
    var needsReviewCount: Int { trades.filter { $0.status == .needsReview }.count }
    var netPnL: Decimal {
        trades.filter(\.isImportable).reduce(0) { $0 + $1.realizedPnL }
    }
    var winCount: Int {
        trades.filter { $0.isImportable && $0.realizedPnL > 0 }.count
    }
    var lossCount: Int {
        trades.filter { $0.isImportable && $0.realizedPnL < 0 }.count
    }
}

nonisolated struct CSVImportResult: Hashable, Codable, Sendable {
    var importedCount: Int
    var netPnL: Decimal
    var skippedInvalidCount: Int
    var failureMessage: String?
}

/// Manual column mapping — CSV header → logical field (or ignore).
nonisolated struct CSVColumnMapping: Hashable, Codable, Sendable, Identifiable {
    var id: String { header }
    var header: String
    var field: CSVLogicalField?
}
