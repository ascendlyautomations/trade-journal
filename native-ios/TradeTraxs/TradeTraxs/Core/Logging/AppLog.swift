import Foundation
import OSLog

/// Centralized logging via Apple `Logger` / `os.Logger`.
///
/// Categories match architecture subsystems. Never log tokens, passwords, or PII.
///
/// Uses a compile-time subsystem string — `Bundle.main` is MainActor-isolated in Swift 6 and
/// must not back shared loggers invoked from repositories or networking.
nonisolated enum AppLog {
    static let subsystem = "com.tradetraxs.TradeTraxs"

    static let application = Logger(subsystem: subsystem, category: "Application")
    static let navigation = Logger(subsystem: subsystem, category: "Navigation")
    static let networking = Logger(subsystem: subsystem, category: "Networking")
    static let authentication = Logger(subsystem: subsystem, category: "Authentication")
    static let realtime = Logger(subsystem: subsystem, category: "Realtime")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let general = Logger(subsystem: subsystem, category: "General")
}
