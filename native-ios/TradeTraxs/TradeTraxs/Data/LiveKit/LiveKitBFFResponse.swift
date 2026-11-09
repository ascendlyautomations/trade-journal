import Foundation

/// Guards LiveKit BFF decoding against HTML/error pages (stale deploy, wrong API_BASE_URL).
nonisolated enum LiveKitBFFResponse {
    static func contentType(_ response: HTTPResponse) -> String {
        let raw =
            response.httpURLResponse.value(forHTTPHeaderField: "Content-Type")
            ?? response.httpURLResponse.value(forHTTPHeaderField: "content-type")
        return raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }

    static func looksLikeHTML(_ response: HTTPResponse) -> Bool {
        let ct = contentType(response).lowercased()
        if ct.contains("text/html") { return true }
        let prefix = String(data: response.data.prefix(80), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if prefix.hasPrefix("<!DOCTYPE") || prefix.lowercased().hasPrefix("<html") {
            return true
        }
        return false
    }

    static func nonJSONMessage(path: String, response: HTTPResponse) -> String {
        let url = response.httpURLResponse.url?.absoluteString ?? path
        let status = response.statusCode
        let ct = contentType(response)
        if path.contains("/obs/") {
            return """
            OBS livestream API is not available at this server (HTTP \(status), \(ct)). \
            The deployed backend may be missing /api/livekit/broadcast/obs/* routes — deploy the latest web app, \
            or set API_BASE_URL in Secrets.plist to your dev server (e.g. http://YOUR_MAC_LAN_IP:3000). \
            URL: \(url)
            """
        }
        return """
        Server returned a web page instead of JSON (HTTP \(status), \(ct)). \
        Check API_BASE_URL points at your Next.js app, not a marketing-only host. URL: \(url)
        """
    }

    #if DEBUG
    static func log(
        path: String,
        method: HTTPMethod,
        requiresAuthentication: Bool,
        response: HTTPResponse
    ) {
        let url = response.httpURLResponse.url?.absoluteString ?? path
        let snippet = TradeRoomObsBroadcastDiagnostics.redactedBodySnippet(response.data, limit: 200)
        print(
            """
            [LiveKitBFF] \(method.rawValue) \(path) \
            auth=\(requiresAuthentication) \
            url=\(url) \
            http=\(response.statusCode) \
            content-type=\(contentType(response)) \
            body=\(snippet)
            """
        )
    }
    #endif
}
