import Foundation

enum BacktestLabChartDrillDown: Equatable, Hashable, Sendable, Identifiable {
    case wins
    case losses
    case session(String)
    case weekday(String)
    case hour(String)
    case long
    case short
    case holdBucket(String)
    case strategy(String)
    case setupTag(String)
    case instrument(String)

    var id: String {
        switch self {
        case .wins: return "wins"
        case .losses: return "losses"
        case .session(let s): return "session:\(s)"
        case .weekday(let s): return "weekday:\(s)"
        case .hour(let h): return "hour:\(h)"
        case .long: return "long"
        case .short: return "short"
        case .holdBucket(let b): return "hold:\(b)"
        case .strategy(let k): return "strategy:\(k)"
        case .setupTag(let k): return "setup:\(k)"
        case .instrument(let k): return "instrument:\(k)"
        }
    }

    var title: String {
        switch self {
        case .wins: return "Winning Trades"
        case .losses: return "Losing Trades"
        case .session(let label): return "\(label) Session"
        case .weekday(let label): return label
        case .hour(let label): return "Hour \(label)"
        case .long: return "Long Trades"
        case .short: return "Short Trades"
        case .holdBucket(let label): return "Hold \(label)"
        case .strategy(let key):
            return key == "__no_strategy__" ? "No Strategy" : key
        case .setupTag(let key): return key
        case .instrument(let key): return key
        }
    }

    func filter(_ trades: [Trade]) -> [Trade] {
        switch self {
        case .wins:
            return trades.filter { ($0.realizedPnL?.amount ?? 0) > 0 }
        case .losses:
            return trades.filter { ($0.realizedPnL?.amount ?? 0) < 0 }
        case .session(let label):
            return trades.filter {
                ($0.sessionLabel ?? "").localizedCaseInsensitiveContains(label)
            }
        case .weekday(let label):
            guard let weekday = TradeHistoryLaunchSeed.calendarWeekday(forHeatmapLabel: label) else {
                return trades
            }
            let calendar = Calendar.current
            return trades.filter { trade in
                let stamp = DashboardScopeFilterSupport.dashboardTradeFilterDate(for: trade)
                let day = calendar.component(.weekday, from: stamp)
                return day == weekday
            }
        case .hour(let label):
            guard let hour = Int(label) else { return trades }
            let calendar = Calendar.current
            return trades.filter { trade in
                let stamp = DashboardScopeFilterSupport.dashboardTradeFilterDate(for: trade)
                return calendar.component(.hour, from: stamp) == hour
            }
        case .long:
            return trades.filter { $0.side == .long }
        case .short:
            return trades.filter { $0.side == .short }
        case .holdBucket(let label):
            guard let range = TradeHistoryLaunchSeed.holdRange(forBucketLabel: label) else {
                return trades
            }
            return trades.filter { trade in
                guard let seconds = trade.durationSeconds else { return false }
                return range.contains(TimeInterval(seconds))
            }
        case .strategy(let key):
            return BacktestLabGroupedPerformance.tradesMatchingStrategy(trades, key: key)
        case .setupTag(let key):
            return BacktestLabGroupedPerformance.tradesMatchingSetupTag(trades, key: key)
        case .instrument(let key):
            return BacktestLabGroupedPerformance.tradesMatchingInstrument(trades, key: key)
        }
    }
}