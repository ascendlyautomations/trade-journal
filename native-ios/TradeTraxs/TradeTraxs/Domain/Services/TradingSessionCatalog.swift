import Foundation

nonisolated enum TradingSessionCatalog {
    static let displayOrder: [String] = [
        "NY AM",
        "NY Lunch",
        "NY PM",
        "London",
        "Asia",
        "After",
    ]

    static func displayTitle(for label: String) -> String {
        switch label {
        case "NY AM": return "New York AM"
        case "NY Lunch": return "New York Lunch"
        case "NY PM": return "New York PM"
        case "London": return "London"
        case "Asia": return "Asia"
        case "After": return "After"
        default: return label
        }
    }
}
