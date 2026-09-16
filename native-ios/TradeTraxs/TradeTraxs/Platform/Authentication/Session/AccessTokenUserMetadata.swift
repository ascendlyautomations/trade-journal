import Foundation

/// Reads non-sensitive `user_metadata` fields from a Supabase access JWT (no token logging).
nonisolated enum AccessTokenUserMetadata {
    static func displayName(from accessToken: String) -> String? {
        guard let metadata = userMetadataDictionary(from: accessToken) else { return nil }

        if let full = stringValue(metadata["full_name"]), let normalized = ProfileDisplayNamePolicy.normalized(full) {
            return normalized
        }
        if let name = stringValue(metadata["name"]), let normalized = ProfileDisplayNamePolicy.normalized(name) {
            return normalized
        }

        let given = stringValue(metadata["given_name"]).flatMap { ProfileDisplayNamePolicy.normalized($0) }
        let family = stringValue(metadata["family_name"]).flatMap { ProfileDisplayNamePolicy.normalized($0) }
        let parts = [given, family].compactMap { $0 }
        if !parts.isEmpty {
            return ProfileDisplayNamePolicy.normalized(parts.joined(separator: " "))
        }
        return nil
    }

    private static func userMetadataDictionary(from accessToken: String) -> [String: Any]? {
        guard let payload = jwtPayloadDictionary(from: accessToken) else { return nil }
        return payload["user_metadata"] as? [String: Any]
    }

    private static func jwtPayloadDictionary(from accessToken: String) -> [String: Any]? {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return json
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

extension OAuthFirstLoginHint {
    static func merged(
        explicit: OAuthFirstLoginHint?,
        session: AuthenticationSession
    ) -> OAuthFirstLoginHint? {
        if let explicit, ProfileDisplayNamePolicy.normalized(explicit.fullName) != nil {
            return explicit
        }
        if session.provider == .google || session.provider == .apple {
            let fromToken = AccessTokenUserMetadata.displayName(from: session.accessToken)
            let hint = normalized(fullName: fromToken, email: session.email)
            if hint.hasContent { return hint }
        }
        return explicit?.hasContent == true ? explicit : nil
    }
}
