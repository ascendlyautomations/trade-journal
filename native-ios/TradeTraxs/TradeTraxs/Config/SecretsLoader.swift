import Foundation

/// Loads non-secret public client configuration from local Secrets.plist / Info.plist / process env.
/// Never commits real Secrets.plist — use ``Secrets.example.plist`` as the template.
nonisolated enum SecretsLoader {
    struct Values: Sendable, Equatable {
        var supabaseURL: URL?
        var supabaseAnonKey: String?
        var apiBaseURL: URL?
    }

    static func load(bundle: Bundle = .main) -> Values {
        let plist = loadPlistDictionary(bundle: bundle)
        let env = ProcessInfo.processInfo.environment

        let supabaseURLString =
            string(from: plist, key: "SUPABASE_URL")
            ?? env["SUPABASE_URL"]
            ?? env["NEXT_PUBLIC_SUPABASE_URL"]
            ?? string(fromInfo: bundle, key: "SUPABASE_URL")

        let anonKey =
            string(from: plist, key: "SUPABASE_ANON_KEY")
            ?? env["SUPABASE_ANON_KEY"]
            ?? env["NEXT_PUBLIC_SUPABASE_ANON_KEY"]
            ?? string(fromInfo: bundle, key: "SUPABASE_ANON_KEY")

        let apiBase =
            string(from: plist, key: "API_BASE_URL")
            ?? env["API_BASE_URL"]
            ?? string(fromInfo: bundle, key: "API_BASE_URL")

        return Values(
            supabaseURL: url(from: supabaseURLString),
            supabaseAnonKey: nonEmpty(anonKey),
            apiBaseURL: url(from: apiBase)
        )
    }

    private static func loadPlistDictionary(bundle: Bundle) -> [String: Any] {
        // Prefer Config/Secrets.plist copied into the app bundle as Secrets.plist.
        if let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dictionary = object as? [String: Any]
        {
            return dictionary
        }
        return [:]
    }

    private static func string(from dictionary: [String: Any], key: String) -> String? {
        nonEmpty(dictionary[key] as? String)
    }

    private static func string(fromInfo bundle: Bundle, key: String) -> String? {
        nonEmpty(bundle.object(forInfoDictionaryKey: key) as? String)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func url(from string: String?) -> URL? {
        guard let string, let url = URL(string: string), url.scheme != nil else { return nil }
        return url
    }
}
