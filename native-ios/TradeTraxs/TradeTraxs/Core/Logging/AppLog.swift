import Foundation
import OSLog

/// Centralized logging via Apple `Logger` / `os.Logger`.
///
/// Categories match architecture subsystems. Never log tokens, passwords, or PII.
enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.tradetraxs.ios"

    static let application = Logger(subsystem: subsystem, category: "Application")
    static let navigation = Logger(subsystem: subsystem, category: "Navigation")
    static let networking = Logger(subsystem: subsystem, category: "Networking")
    static let authentication = Logger(subsystem: subsystem, category: "Authentication")
    static let realtime = Logger(subsystem: subsystem, category: "Realtime")
    static let general = Logger(subsystem: subsystem, category: "General")
}
