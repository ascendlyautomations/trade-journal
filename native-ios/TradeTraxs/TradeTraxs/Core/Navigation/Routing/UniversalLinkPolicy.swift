import Foundation

enum UniversalLinkPolicy {
    static func isSupportedHTTPSHost(_ url: URL) -> Bool {
        let scheme = (url.scheme ?? "").lowercased()
        guard scheme == "https" || scheme == "http" else { return false }
        let host = (url.host ?? "").lowercased()
        return host == "www.tradetraxs.com" || host == "tradetraxs.com"
    }
}
