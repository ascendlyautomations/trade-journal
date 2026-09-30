import Foundation

nonisolated enum CSVImportFixtures {
    /// Tradovate Performance export row shape (24-hour local timestamps).
    static let tradovatePerformanceRowCSV = """
    symbol,buyPrice,sellPrice,qty,pnl,boughtTimestamp,soldTimestamp
    MNQM6,28331.75,28320.25,1,$(69.00),05/05/2026 20:11:36,05/05/2026 20:13:52
    """

    /// Full Performance export header (13 columns) with CRLF — matches real device file shape.
    static let tradovatePerformanceExportCRLF: String = {
        let rows = [
            "symbol,priceFormat,priceFormatType,tickSize,buyFillId,sellFillId,qty,buyPrice,sellPrice,pnl,boughtTimestamp,soldTimestamp,duration",
            "MGCM6,1,0,0.1,660290950163,660290950170,1,4348.4,4348.1,\"$(3.00)\",05/05/2026 20:11:36,05/05/2026 20:11:40,0:00:15",
            "MNQM6,1,0,0.25,660290950007,660290950014,1,28331.75,28320.25,\"$(69.00)\",05/05/2026 20:11:36,05/05/2026 20:13:52,0:02:16",
        ]
        return rows.joined(separator: "\r\n")
    }()

    /// Same rows separated by Unicode line separator (PapaParse-compatible).
    static let tradovatePerformanceExportUnicodeLines: String = {
        let rows = [
            "symbol,priceFormat,priceFormatType,tickSize,buyFillId,sellFillId,qty,buyPrice,sellPrice,pnl,boughtTimestamp,soldTimestamp,duration",
            "MGCM6,1,0,0.1,660290950163,,1,4348.4,4348.1,$(3.00),05/05/2026 20:11:36,05/05/2026 20:11:40,",
            "MNQM6,1,0,0.25,,660290950014,1,28331.75,28320.25,$(69.00),05/05/2026 20:11:36,05/05/2026 20:13:52,0:02:16",
        ]
        return rows.joined(separator: "\u{2028}")
    }()

    /// Synthetic Tradovate-shaped export (web detection headers).
    static let tradovateCSV = """
    symbol,buyPrice,sellPrice,qty,pnl,boughtTimestamp,soldTimestamp,side
    MNQM6,21450.25,21463.00,2,437.50,2026-03-10T14:32:00Z,2026-03-10T14:36:00Z,Buy
    NQZ25,18500.00,18490.00,1,-150.00,2026-03-10T15:04:00Z,2026-03-10T15:05:00Z,Sell
    ES,5200.00,5210.50,1,525.00,2026-03-10T16:00:00Z,2026-03-10T16:12:00Z,Long
    """

    /// Flexible generic CSV matching Date/Symbol/Direction/PnL aliases.
    static let flexibleCSV = """
    Date,Symbol,Direction,PnL,Entry Price,Exit Price,Quantity,RR
    2026-01-15,NQ,Long,150,18000,18010,2,2.5
    2026-01-15,ES,Short,-80,5200,5204,1,
    2026-01-16,MNQ,Buy,220,21400,21411,3,1.8
    """

    /// Unknown headers — requires manual mapping.
    static let unknownCSV = """
    Widget,Flip,Beans,Cash
    Alpha,Up,2,100
    Beta,Down,1,-40
    """

    /// Entered/Exited style (NinjaTrader / TopStep shaped).
    static let enteredExitedCSV = """
    Symbol,EnteredAt,ExitedAt,EntryPrice,ExitPrice,PnL,Qty,Side
    MNQ,2026-02-01 09:30:00,2026-02-01 09:35:00,21400,21410,200,2,Long
    NQ,2026-02-01 10:00:00,2026-02-01 10:02:00,18500,18495,-100,1,Short
    """

    /// Golden Math Audit header — separate `date` + 24-hour `entry time` / `exit time`.
    static let goldenMathAuditHeader =
        "date,symbol,direction,pnl,entry price,exit price,contracts,entry time,exit time,rr,points,session,strategy,notes,commission,fees"

    static func goldenMathAuditRow(entryTime: String, exitTime: String = "10:14:00") -> String {
        "2026-01-05,MNQ,Long,100,21400,21410,1,\(entryTime),\(exitTime),1,10,NY,Scalp,note,0,0"
    }

    static func goldenMathAuditCSV(entryTime: String, exitTime: String = "10:14:00") -> String {
        "\(goldenMathAuditHeader)\n\(goldenMathAuditRow(entryTime: entryTime, exitTime: exitTime))"
    }

    /// Session crosses midnight on the same trade date (Golden Math Audit rows).
    static let goldenMathAuditMidnightCrossCSV = """
    \(goldenMathAuditHeader)
    2026-02-03,MNQ,Long,50,21400,21410,1,22:50:00,00:14:00,1,10,Asia,Trend,audit,,0,0
    """

    /// Shared header; row 1 flexible, row 2 Entered/Exited (web per-row dispatch).
    static let mixedNonTradovateCSV = """
    Date,Symbol,Direction,PnL,EnteredAt,ExitedAt,EntryPrice,ExitPrice,Qty,Side
    2026-01-15,NQ,Long,100,,,,,,
    2026-01-15,MNQ,,200,2026-02-01 09:30:00,2026-02-01 09:35:00,21400,21410,2,Long
    """

    static let quotedCommaCSV = """
    symbol,buyPrice,sellPrice,qty,pnl,boughtTimestamp,soldTimestamp
    "MNQ,M6",4348.4,4348.1,1,"$(3.00)",05/05/2026 20:11:36,05/05/2026 20:11:40
    """

    static let flexibleWithDurationCSV = """
    Date,Symbol,Direction,PnL,Duration
    2026-01-15,NQ,Long,50,0:44:00
    """
}
