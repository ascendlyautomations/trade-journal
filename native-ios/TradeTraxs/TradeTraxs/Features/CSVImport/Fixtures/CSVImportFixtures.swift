import Foundation

enum CSVImportFixtures {
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
}
