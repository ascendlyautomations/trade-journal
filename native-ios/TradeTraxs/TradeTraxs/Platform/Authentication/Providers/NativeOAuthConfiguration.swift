import CryptoKit
import Foundation
import Security

/// Native iOS OAuth URLs — must match ``lib/nativeIosOAuthUrls.ts`` and Supabase allow-list.
nonisolated enum NativeOAuthConfiguration {
    static let callbackScheme = "tradetraxs"
    static let callbackDeepLink = "tradetraxs://auth/callback"

    /// Production HTTPS bridge used as Supabase `redirect_to` (never a bare custom scheme).
    static func httpsBridgeURL(configuration: AppConfiguration) -> URL {
        let base = configuration.apiBaseURL ?? AppConfiguration.productionBFFBaseURL
        var baseString = base.absoluteString
        if baseString.hasSuffix("/") { baseString.removeLast() }
        guard let url = URL(string: baseString + "/api/auth/native-callback") else {
            return URL(string: "https://www.tradetraxs.com/api/auth/native-callback")!
        }
        return url
    }

    static func isOAuthCallbackURL(_ url: URL) -> Bool {
        let scheme = (url.scheme ?? "").lowercased()
        guard scheme == callbackScheme else { return false }
        var parts: [String] = []
        if let host = url.host, !host.isEmpty {
            parts.append(host)
        }
        parts.append(contentsOf: url.path.split(separator: "/").map(String.init))
        guard parts.count >= 2 else { return false }
        return parts[0] == "auth" && parts[1] == "callback"
    }

    static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64URLEncodedString()
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    static func fragmentOrQueryItems(from url: URL) -> [String: String] {
        var values: [String: String] = [:]
        if let fragment = url.fragment {
            for pair in fragment.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    values[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
                }
            }
        }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items {
                if let value = item.value {
                    values[item.name] = value
                }
            }
        }
        return values
    }
}

private nonisolated extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
