import Foundation

/// Safe `DecodingError` diagnostics — never logs response bodies or user data.
nonisolated enum BackendV2DecodingDiagnostics {
    struct Snapshot: Sendable, Equatable {
        var category: String
        var codingPath: String
        var expectedType: String?
        var missingKey: String?
        var debugDescription: String
    }

    static func snapshot(from error: Error) -> Snapshot? {
        guard let decoding = error as? DecodingError else { return nil }
        switch decoding {
        case .keyNotFound(let key, let context):
            return Snapshot(
                category: "keyNotFound",
                codingPath: path(context),
                expectedType: nil,
                missingKey: key.stringValue,
                debugDescription: sanitize(context.debugDescription)
            )
        case .valueNotFound(let type, let context):
            return Snapshot(
                category: "valueNotFound",
                codingPath: path(context),
                expectedType: String(describing: type),
                missingKey: nil,
                debugDescription: sanitize(context.debugDescription)
            )
        case .typeMismatch(let type, let context):
            return Snapshot(
                category: "typeMismatch",
                codingPath: path(context),
                expectedType: String(describing: type),
                missingKey: nil,
                debugDescription: sanitize(context.debugDescription)
            )
        case .dataCorrupted(let context):
            return Snapshot(
                category: "dataCorrupted",
                codingPath: path(context),
                expectedType: nil,
                missingKey: nil,
                debugDescription: sanitize(context.debugDescription)
            )
        @unknown default:
            return Snapshot(
                category: "unknown",
                codingPath: "",
                expectedType: nil,
                missingKey: nil,
                debugDescription: sanitize(decoding.localizedDescription)
            )
        }
    }

    static func trace(rpcName: String, correlation: String, error: Error) {
        #if DEBUG
        guard let snap = snapshot(from: error) else { return }
        var parts = [
            "category=\(snap.category)",
            "path=\(snap.codingPath)",
        ]
        if let expected = snap.expectedType {
            parts.append("expected=\(expected)")
        }
        if let key = snap.missingKey {
            parts.append("key=\(key)")
        }
        parts.append("description=\(snap.debugDescription)")
        BackendV2RpcStageTracer.trace(
            rpcName,
            stage: "decoder.failed",
            correlation: correlation,
            detail: parts.joined(separator: " ")
        )
        #endif
    }

    private static func path(_ context: DecodingError.Context) -> String {
        context.codingPath.map(\.stringValue).joined(separator: ".")
    }

    private static func sanitize(_ text: String) -> String {
        var value = text
        let redactedMarkers = [
            "Bearer ", "eyJ", "apikey", "Authorization", "token",
            "notes", "note", "account_name", "name", "screenshot", "image_url",
        ]
        for marker in redactedMarkers where value.localizedCaseInsensitiveContains(marker) {
            value = "[redacted]"
            break
        }
        if value.count > 240 {
            value = String(value.prefix(240))
        }
        return value
    }
}
