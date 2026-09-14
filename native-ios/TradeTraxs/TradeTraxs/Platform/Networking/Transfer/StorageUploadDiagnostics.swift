import Foundation

enum StorageUploadDiagnostics {
    struct ObjectLocation: Sendable {
        var bucket: String
        var path: String
    }

    static func parseObjectLocation(from url: URL) -> ObjectLocation? {
        let marker = "/storage/v1/object/"
        let raw = url.path
        guard let range = raw.range(of: marker) else { return nil }
        let remainder = String(raw[range.upperBound...])
        guard let slash = remainder.firstIndex(of: "/") else { return nil }
        let bucket = String(remainder[..<slash])
        let path = String(remainder[remainder.index(after: slash)...])
        guard !bucket.isEmpty, !path.isEmpty else { return nil }
        return ObjectLocation(bucket: bucket, path: path)
    }

    static func logRequest(
        bucket: String,
        path: String,
        method: String,
        request: URLRequest,
        uploadPayloadBytes: Int
    ) {
        let auth = request.value(forHTTPHeaderField: "Authorization")
        let scheme = auth?.split(separator: " ").first.map(String.init)
        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        let hasAPIKey = request.value(forHTTPHeaderField: "apikey") != nil
        print(
            """
            [STORAGE_UPLOAD_REQUEST] bucket=\(bucket) \
            path=\(path) \
            method=\(method) \
            hasAuthorization=\(auth != nil && !(auth?.isEmpty ?? true)) \
            authorizationScheme=\(scheme ?? "none") \
            hasAPIKey=\(hasAPIKey) \
            contentType=\(contentType) \
            bodyInRequest=\((request.httpBody != nil) || (request.httpBodyStream != nil)) \
            uploadPayloadBytes=\(uploadPayloadBytes)
            """
        )
    }

    static func logResponse(
        bucket: String,
        path: String,
        statusCode: Int,
        supabaseCode: String?,
        responseData: Data
    ) {
        let code = supabaseCode ?? parseSupabaseCode(from: responseData) ?? "none"
        print(
            """
            [STORAGE_UPLOAD_RESPONSE] bucket=\(bucket) \
            path=\(path) \
            statusCode=\(statusCode) \
            supabaseCode=\(code)
            """
        )
    }

    static func parseSupabaseCode(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let code = object["code"] as? String
        else { return nil }
        return code
    }
}
