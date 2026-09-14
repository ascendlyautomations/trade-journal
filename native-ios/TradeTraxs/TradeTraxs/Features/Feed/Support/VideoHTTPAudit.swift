import Foundation

#if DEBUG
/// Temporary DEBUG probe — verifies Supabase/public object Range support without replacing AVPlayer.
enum VideoHTTPAudit {
    static func probe(url: URL, clipID: String, surface: String, role: String) {
        Task.detached(priority: .utility) {
            await runProbe(url: url, clipID: clipID, surface: surface, role: role)
        }
    }

    private static func runProbe(url: URL, clipID: String, surface: String, role: String) async {
        await logResponse(
            clipID: clipID,
            surface: surface,
            role: role,
            label: "HEAD",
            requestedRange: nil,
            response: await fetch(url: url, method: "HEAD", range: nil)
        )
        await logResponse(
            clipID: clipID,
            surface: surface,
            role: role,
            label: "RANGE",
            requestedRange: "bytes=0-65535",
            response: await fetch(url: url, method: "GET", range: "bytes=0-65535")
        )
    }

    private struct ProbeResponse: Sendable {
        var statusCode: Int
        var contentLength: String
        var contentRange: String
        var acceptRanges: String
        var responseBytes: Int
    }

    private static func fetch(url: URL, method: String, range: String?) async -> ProbeResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let range {
            request.setValue(range, forHTTPHeaderField: "Range")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let headers = http?.allHeaderFields ?? [:]
            return ProbeResponse(
                statusCode: http?.statusCode ?? -1,
                contentLength: headerString("Content-Length", from: headers),
                contentRange: headerString("Content-Range", from: headers),
                acceptRanges: headerString("Accept-Ranges", from: headers),
                responseBytes: data.count
            )
        } catch {
            return ProbeResponse(
                statusCode: -1,
                contentLength: "error",
                contentRange: error.localizedDescription,
                acceptRanges: "unknown",
                responseBytes: 0
            )
        }
    }

    private static func headerString(_ name: String, from headers: [AnyHashable: Any]) -> String {
        for (key, value) in headers {
            guard let keyString = key as? String, keyString.caseInsensitiveCompare(name) == .orderedSame else {
                continue
            }
            return String(describing: value)
        }
        return "none"
    }

    private static func logResponse(
        clipID: String,
        surface: String,
        role: String,
        label: String,
        requestedRange: String?,
        response: ProbeResponse
    ) async {
        print(
            """
            [VideoHTTPAudit] \
            clipID=\(clipID) \
            surface=\(surface) \
            role=\(role) \
            probe=\(label) \
            statusCode=\(response.statusCode) \
            contentLength=\(response.contentLength) \
            contentRange=\(response.contentRange) \
            acceptRanges=\(response.acceptRanges) \
            requestedRange=\(requestedRange ?? "none") \
            responseBytes=\(response.responseBytes)
            """
        )
    }
}
#else
enum VideoHTTPAudit {
    static func probe(url: URL, clipID: String, surface: String, role: String) {}
}
#endif
