import Foundation

/// Converts external URLs into typed ``AppDestination`` values.
protocol DeepLinkParsing: Sendable {
    func parse(url: URL) -> AppDestination?
}

/// Production deep-link / universal-link parser.
///
/// Supports:
/// - `https://www.tradetraxs.com/...` / `https://tradetraxs.com/...`
/// - `tradetraxs://...` / `com.tradetraxs.TradeTraxs://...`
/// - legacy `com.tradetraxs.ios://...` (retired Capacitor identity)
///
/// Features never parse URLs themselves — they only consume destinations.
struct DeepLinkParser: DeepLinkParsing {
    func parse(url: URL) -> AppDestination? {
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "tradetraxs"
            || scheme == "com.tradetraxs.tradetraxs"
            || scheme == "com.tradetraxs.ios"
        {
            return parseCustomScheme(url)
        }
        if scheme == "https" || scheme == "http" {
            return parseHTTPS(url)
        }
        return nil
    }

    private func parseHTTPS(_ url: URL) -> AppDestination? {
        let host = (url.host ?? "").lowercased()
        guard host == "www.tradetraxs.com" || host == "tradetraxs.com" else {
            return nil
        }
        return parsePath(url.pathComponentsFiltered, query: url.queryItemsDictionary)
    }

    private func parseCustomScheme(_ url: URL) -> AppDestination? {
        var parts = url.pathComponentsFiltered
        if let host = url.host, !host.isEmpty {
            parts.insert(host, at: 0)
        }
        return parsePath(parts, query: url.queryItemsDictionary)
    }

    private func parsePath(_ parts: [String], query: [String: String]) -> AppDestination? {
        guard let first = parts.first else {
            return .tab(.home)
        }

        switch first {
        case "login", "auth":
            if let second = parts[safe: 1] {
                switch second {
                case "onboarding":
                    return .auth(.onboarding)
                case "reset-password", "forgot-password", "resetPassword":
                    return .auth(.resetPassword)
                case "choose-plan":
                    return .auth(.choosePlan)
                case "finish-trial":
                    return .auth(.finishTrial)
                default:
                    return .auth(.login)
                }
            }
            return .auth(.login)
        case "onboarding":
            return .auth(.onboarding)
        case "reset-password", "forgot-password", "resetPassword":
            return .auth(.resetPassword)
        case "choose-plan":
            return .auth(.choosePlan)
        case "dashboard", "home":
            return parseHome(Array(parts.dropFirst()))
        case "trades":
            return .home(.trades)
        case "trade":
            if let id = parts[safe: 1] {
                return .home(.tradeDetail(TradeID(id)))
            }
            return .home(.trades)
        case "calendar":
            return .home(.calendar)
        case "analyst", "ai":
            return .home(.analyst)
        case "feed":
            return parseFeed(Array(parts.dropFirst()))
        case "explore":
            return .feed(.explore)
        case "leaderboard":
            return .feed(.leaderboard)
        case "community", "trade-rooms":
            return parseRooms(Array(parts.dropFirst()), query: query)
        case "room":
            if let id = parts[safe: 1] {
                return .feed(.room(RoomID(id)))
            }
            return .feed(.rooms)
        case "post":
            if let id = parts[safe: 1] {
                return .feed(.post(PostID(id)))
            }
            return .tab(.feed)
        case "reel":
            if let id = parts[safe: 1] {
                return .feed(.reel(ReelID(id)))
            }
            return .tab(.feed)
        case "story":
            if let id = parts[safe: 1] {
                return .feed(.story(StoryID(id)))
            }
            return .tab(.feed)
        case "messages":
            if let id = parts[safe: 1] {
                return .messages(.thread(ConversationID(id)))
            }
            return .tab(.messages)
        case "notifications":
            return .profile(.activity)
        case "profile":
            if let id = parts[safe: 1] {
                return .feed(.profile(ProfileID(id)))
            }
            return .tab(.profile)
        case "settings":
            return parseSettings(Array(parts.dropFirst()))
        case "app", "input-trade", "input":
            return .compose(.trade)
        case "import":
            return .compose(.importCSV)
        default:
            return nil
        }
    }

    private func parseHome(_ parts: [String]) -> AppDestination {
        guard let second = parts.first else { return .tab(.home) }
        switch second {
        case "trades":
            return .home(.trades)
        default:
            return .tab(.home)
        }
    }

    private func parseFeed(_ parts: [String]) -> AppDestination {
        guard let second = parts.first else { return .tab(.feed) }
        switch second {
        case "explore": return .feed(.explore)
        default: return .tab(.feed)
        }
    }

    private func parseRooms(_ parts: [String], query: [String: String]) -> AppDestination {
        // Trade Room deep links open through Messages (DM-style shell + channel switcher).
        if let roomQuery = query["room"] {
            return .messages(.room(RoomID(roomQuery)))
        }
        if let id = parts.first {
            return .messages(.room(RoomID(id)))
        }
        return .tab(.messages)
    }

    /// Builds Settings stack: home → section → optional leaf (e.g. notifications/messages).
    private func parseSettings(_ parts: [String]) -> AppDestination {
        guard let first = parts.first else {
            return .settingsStack([.home])
        }
        // Nested: settings/notifications/messages
        if first == "notifications", let leaf = parts[safe: 1] {
            let leafRoute = SettingsRoute.fromDeepLinkSegment(leaf) ?? .notificationsMessages
            return .settingsStack([.home, .notifications, leafRoute])
        }
        guard let route = SettingsRoute.fromDeepLinkSegment(first) else {
            return .settingsStack([.home])
        }
        if route == .home {
            return .settingsStack([.home])
        }
        return .settingsStack([.home, route])
    }
}

extension URL {
    var pathComponentsFiltered: [String] {
        pathComponents.filter { $0 != "/" && !$0.isEmpty }
    }

    var queryItemsDictionary: [String: String] {
        guard let items = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }
        var result: [String: String] = [:]
        for item in items {
            if let value = item.value {
                result[item.name] = value
            }
        }
        return result
    }
}

private extension Array where Element == String {
    subscript(safe index: Int) -> String? {
        indices.contains(index) ? self[index] : nil
    }
}
