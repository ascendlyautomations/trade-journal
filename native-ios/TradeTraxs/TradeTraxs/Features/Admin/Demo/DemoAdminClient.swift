import Foundation

/// Settings → Admin → Demo Mode is visible only when session bootstrap says this user is in `admin_users`.
nonisolated enum DemoAdminEntry {
    static let rowTitle = "Demo Mode"
    static func isAvailable(isPlatformAdmin: Bool) -> Bool {
        isPlatformAdmin
    }
}

nonisolated enum DemoAdminError: Error, Equatable {
    case failed(String)
    case validation([String])
    case accessRequired

    var message: String {
        switch self {
        case .failed(let text):
            return text
        case .validation(let issues):
            return issues.joined(separator: "\n")
        case .accessRequired:
            return "Admin access is required."
        }
    }
}

nonisolated struct DemoAdminVersion: Equatable, Sendable, Identifiable {
    var version: Int
    var publishedAt: String?
    var isCurrent: Bool
    var id: Int { version }
}

nonisolated struct DemoAdminState: Equatable, Sendable {
    var ok: Bool
    var error: String?
    var errors: [String]
    var publishedVersion: Int?
    var history: [DemoAdminVersion]
    var draft: Data

    static func parse(_ data: Data) throws -> DemoAdminState {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let published = json["published"] as? [String: Any]
        let history = (json["history"] as? [[String: Any]] ?? []).map { row in
            DemoAdminVersion(
                version: DemoJSON.int(row["version"]) ?? 0,
                publishedAt: DemoJSON.string(row["publishedAt"]),
                isCurrent: DemoJSON.bool(row["isCurrent"]) == true
            )
        }
        let draft = json["draft"] as? [String: Any] ?? [:]
        let draftData = (try? JSONSerialization.data(withJSONObject: draft)) ?? Data("{}".utf8)
        let errors = (json["errors"] as? [Any] ?? []).map { DemoJSON.string($0) ?? "" }.filter { !$0.isEmpty }
        return DemoAdminState(
            ok: DemoJSON.bool(json["ok"]) != false,
            error: DemoJSON.string(json["error"]),
            errors: errors,
            publishedVersion: DemoJSON.int(json["publishedVersion"]) ?? DemoJSON.int(published?["version"]),
            history: history,
            draft: draftData
        )
    }
}

nonisolated protocol DemoAdminRPCClient: Sendable {
    func rpc(functionName: String, body: Data) async throws -> Data
}

nonisolated protocol DemoAdminMediaTransport: Sendable {
    func upload(data: Data, mime: String, filename: String, entityType: String, entityId: String, kind: String) async throws -> String
    func release(paths: [String]) async throws
}

nonisolated struct DatabaseDemoAdminRPC: DemoAdminRPCClient {
    let database: any SupabaseDatabaseExecuting

    func rpc(functionName: String, body: Data) async throws -> Data {
        try await database.rpcData(functionName: functionName, parametersJSON: body)
    }
}

nonisolated struct LiveDemoAdminMedia: DemoAdminMediaTransport {
    let transport: SupabaseTransport

    func upload(data: Data, mime: String, filename: String, entityType: String, entityId: String, kind: String) async throws -> String {
        let boundary = "demo-\(UUID().uuidString)"
        let body = DemoMultipart.body(
            fields: ["entityType": entityType, "entityId": entityId, "kind": kind],
            fileField: "file",
            filename: filename,
            mime: mime,
            file: data,
            boundary: boundary
        )
        let response = try await transport.send(
            host: .bff,
            path: "/api/admin/demo/media",
            method: .post,
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
            body: body,
            requiresAuthentication: true
        )
        let json = (try? JSONSerialization.jsonObject(with: response.data)) as? [String: Any]
        guard let url = json?["url"] as? String, !url.isEmpty else {
            throw DemoAdminError.failed("Upload failed. The current Demo media was left unchanged.")
        }
        return url
    }

    func release(paths: [String]) async throws {
        let unique = Array(Set(paths.filter(DemoMediaPath.isOwned)))
        guard !unique.isEmpty else { return }
        let body = try JSONSerialization.data(withJSONObject: ["paths": unique])
        _ = try await transport.send(
            host: .bff,
            path: "/api/admin/demo/media",
            method: .delete,
            headers: ["Content-Type": "application/json"],
            body: body,
            requiresAuthentication: true
        )
    }
}

/// Thin client for `rpc_v1_admin_demo`. Save publishes through that same RPC.
nonisolated struct DemoAdminService: Sendable {
    static let rpcFunction = "rpc_v1_admin_demo"

    var rpc: any DemoAdminRPCClient
    var media: (any DemoAdminMediaTransport)?

    func load() async throws -> DemoAdminState {
        try await command("state", [:])
    }

    func saveAndPublish(entity: String, record: [String: Any], role: String? = nil) async throws -> DemoAdminState {
        var payload: [String: Any] = ["entity": entity, "record": record]
        if let role { payload["role"] = role }
        return try await mutate("save", payload)
    }

    func deleteAndPublish(entity: String, id: String, roomID: String? = nil, profileID: String? = nil) async throws -> DemoAdminState {
        var payload: [String: Any] = ["entity": entity, "id": id]
        if let roomID { payload["roomID"] = roomID }
        if let profileID { payload["profileID"] = profileID }
        return try await mutate("delete", payload)
    }

    func restore(version: Int) async throws -> DemoAdminState {
        let restored = try await command("restore", ["version": version])
        if !restored.ok || !restored.errors.isEmpty {
            throw DemoAdminError.validation(restored.errors.isEmpty ? [restored.error ?? "Could not restore that version."] : restored.errors)
        }
        return restored
    }

    func uploadMedia(data: Data, mime: String, filename: String, entityType: String, entityId: String, kind: String) async throws -> String {
        guard let media else {
            throw DemoAdminError.failed("Demo media upload is unavailable.")
        }
        return try await media.upload(data: data, mime: mime, filename: filename, entityType: entityType, entityId: entityId, kind: kind)
    }

    func releaseMedia(paths: [String]) async {
        guard let media else { return }
        try? await media.release(paths: paths)
    }

    private func mutate(_ name: String, _ payload: [String: Any]) async throws -> DemoAdminState {
        let saved = try await command(name, payload)
        let previous = saved.publishedVersion
        if !saved.ok {
            DemoSnapshotLog.event("admin previous=\(previous.map(String.init) ?? "none") save=failed publish=skipped published=none")
            throw DemoAdminError.failed(saved.error ?? saved.errors.first ?? "Could not save Demo content.")
        }
        let published = try await command("publish", [:])
        if !published.ok || !published.errors.isEmpty {
            _ = try? await command("discard", [:])
            DemoSnapshotLog.event("admin previous=\(previous.map(String.init) ?? "none") save=ok publish=failed published=none")
            let issues = published.errors.isEmpty ? [published.error ?? "Demo could not be published."] : published.errors
            throw DemoAdminError.validation(issues)
        }
        DemoSnapshotLog.event("admin previous=\(previous.map(String.init) ?? "none") save=ok publish=ok published=\(published.publishedVersion.map(String.init) ?? "none")")
        return published
    }

    private func command(_ name: String, _ payload: [String: Any]) async throws -> DemoAdminState {
        let body = try JSONSerialization.data(withJSONObject: ["p_command": name, "p_payload": payload])
        let data: Data
        do {
            data = try await rpc.rpc(functionName: Self.rpcFunction, body: body)
        } catch {
            if DemoAdminService.isAdminRejection(error) {
                throw DemoAdminError.accessRequired
            }
            throw DemoAdminError.failed(DemoAdminService.friendly(error))
        }
        return try DemoAdminState.parse(data)
    }

    static func isAdminRejection(_ error: Error) -> Bool {
        if error is DemoAdminError { return false }
        let text = String(describing: error).lowercased()
        if text.contains("42501") || text.contains("forbidden") { return true }
        if let app = error as? AppError, case .authentication = app { return true }
        return false
    }

    static func friendly(_ error: Error) -> String {
        if let demo = error as? DemoAdminError { return demo.message }
        if let app = error as? AppError, case .unknown(let message) = app { return message }
        if let app = error as? AppError, case .transport(let network) = app,
           case NetworkError.validation(_, let message) = network
        {
            if let data = message.data(using: String.Encoding.utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["error"] as? String
            {
                return text
            }
            return "Upload failed. The current Demo media was left unchanged."
        }
        return "Could not update Demo Mode."
    }
}

extension DataEnvironment {
    func demoAdminService() -> DemoAdminService {
        DemoAdminService(
            rpc: DatabaseDemoAdminRPC(database: supabase.database),
            media: supabase.transport.map(LiveDemoAdminMedia.init)
        )
    }
}

/// Writes an uploaded Demo media URL into the editor record before Save publishes it.
nonisolated enum DemoAdminMediaAssignment {
    static func apply(form: inout DemoObject, path: String, objectKey: String?, url: String, kind: String, array: Bool) {
        let key = objectKey ?? path
        if path == "imageURL" {
            form.set(path, url.isEmpty ? nil : url)
        } else if array {
            form.set(key, url.isEmpty ? [] : [["id": url, "kind": "image", "altText": "Post"]])
        } else {
            form.set(key, url.isEmpty ? nil : ["id": url, "kind": kind, "altText": key])
        }
    }
}

nonisolated enum DemoMediaPath {
    static func isOwned(_ path: String) -> Bool {
        guard !path.isEmpty, !path.contains(".."), !path.contains("\\"), !path.hasPrefix("/"), !path.contains("//") else {
            return false
        }
        return path.range(of: #"^demo/(profile|trade|post|clip|story|achievement|room|payout)/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    static func from(url: String) -> String? {
        guard let range = url.range(of: "/demo-media/") else { return nil }
        let raw = String(url[range.upperBound...]).split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? ""
        let path = raw.removingPercentEncoding ?? raw
        return isOwned(path) ? path : nil
    }
}

nonisolated enum DemoMultipart {
    static func body(fields: [String: String], fileField: String, filename: String, mime: String, file: Data, boundary: String) -> Data {
        var data = Data()
        for (key, value) in fields {
            data.append("--\(boundary)\r\n")
            data.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            data.append("\(value)\r\n")
        }
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
        data.append("Content-Type: \(mime)\r\n\r\n")
        data.append(file)
        data.append("\r\n--\(boundary)--\r\n")
        return data
    }
}

nonisolated enum DemoJSON {
    static func object(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            return text
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.stringValue
        case let number as Int:
            return String(number)
        case let number as Double:
            return String(number)
        default:
            return nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.intValue
        case let number as Int:
            return number
        default:
            return nil
        }
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let flag as Bool:
            return flag
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            return number.boolValue
        default:
            return nil
        }
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.doubleValue
        case let number as Double:
            return number
        case let number as Int:
            return Double(number)
        default:
            return nil
        }
    }

    static func records(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }
}

nonisolated struct DemoObject {
    var storage: [String: Any]

    init(_ storage: [String: Any] = [:]) {
        self.storage = storage
    }

    func value(_ path: String) -> Any? {
        var current: Any? = storage
        for key in path.split(separator: ".").map(String.init) {
            current = (current as? [String: Any])?[key]
        }
        return current
    }

    func string(_ path: String) -> String {
        DemoJSON.string(value(path)) ?? ""
    }

    func bool(_ path: String) -> Bool? {
        DemoJSON.bool(value(path))
    }

    func money(_ path: String) -> Double? {
        guard let object = value(path) as? [String: Any] else { return nil }
        return DemoJSON.double(object["amount"])
    }

    mutating func set(_ path: String, _ newValue: Any?) {
        let keys = path.split(separator: ".").map(String.init)
        storage = Self.write(storage, keys: keys, value: newValue)
    }

    func jsonObject() -> [String: Any] { storage }

    private static func write(_ source: [String: Any], keys: [String], value: Any?) -> [String: Any] {
        guard let key = keys.first else { return source }
        var next = source
        if keys.count == 1 {
            if let value {
                next[key] = value
            } else {
                next[key] = NSNull()
            }
            return next
        }
        let child = next[key] as? [String: Any] ?? [:]
        next[key] = write(child, keys: Array(keys.dropFirst()), value: value)
        return next
    }
}

nonisolated enum DemoAdminLabels {
    static let viewerID = "demo.explore.trader"
    static let emotions = ["Confident", "Calm", "Focused", "Fearful", "FOMO", "Overconfident", "Hesitant", "Frustrated"]
    static let stress = ["Calm", "Slightly Stressed", "Moderate", "Stressed", "Very Stressed"]

    static func money(_ amount: Double?) -> String {
        guard let amount else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"
        if amount > 0 { return "+$\(number)" }
        if amount < 0 { return "-$\(number)" }
        return "$\(number)"
    }

    static func mode(_ value: String) -> String {
        switch value {
        case "evaluation": return "Evaluation"
        case "funded": return "Funded"
        case "live": return "Live"
        case "sim": return "Sim"
        case "backtest": return "Backtest"
        case "propFirm": return "Prop firm"
        case "broker": return "Broker"
        case "personal": return "Personal"
        default: return value.prefix(1).uppercased() + value.dropFirst()
        }
    }

    static func profile(_ record: DemoObject) -> String {
        let name = record.string("displayName").isEmpty ? record.string("username") : record.string("displayName")
        let username = record.string("username")
        if name.isEmpty { return "Profile" }
        return username.isEmpty ? name : "\(name) (@\(username))"
    }

    static func account(_ record: DemoObject) -> String {
        let name = record.string("name").isEmpty ? "Account" : record.string("name")
        let mode = record.string("mode")
        return mode.isEmpty ? name : "\(name) · \(self.mode(mode))"
    }

    static func trade(_ record: DemoObject, account: String) -> String {
        let ticker = record.string("symbol.ticker").isEmpty ? "Trade" : record.string("symbol.ticker")
        let when = String(record.string("entryAt").prefix(10))
        return [ticker, money(record.money("realizedPnL")), account, when].filter { !$0.isEmpty && $0 != "—" }.joined(separator: " · ")
    }

    static func profiles(in draft: [String: Any]) -> [(id: String, label: String, role: String, record: DemoObject)] {
        DemoJSON.records(draft["profiles"]).map { row in
            let record = DemoObject(row["record"] as? [String: Any] ?? [:])
            return (record.string("id"), profile(record), DemoJSON.string(row["role"]) ?? "peer", record)
        }
    }

    static func rows(_ draft: [String: Any], _ key: String) -> [DemoObject] {
        DemoJSON.records(draft[key]).map(DemoObject.init)
    }

    static func humanize(_ issue: String, draft: [String: Any]) -> String {
        var labels: [String: String] = [:]
        for profile in profiles(in: draft) where !profile.id.isEmpty {
            labels[profile.id] = profile.label
        }
        let accounts = rows(draft, "accounts")
        for account in accounts where !account.string("id").isEmpty {
            labels[account.string("id")] = self.account(account)
        }
        for trade in rows(draft, "trades") where !trade.string("id").isEmpty {
            let account = accounts.first { $0.string("id") == trade.string("accountID") }
            let accountLabel = account.map { self.account($0) } ?? ""
            labels[trade.string("id")] = self.trade(trade, account: accountLabel)
        }
        var text = issue
        for (id, label) in labels where !id.isEmpty {
            text = text.replacingOccurrences(of: id, with: label)
        }
        return text
    }
}

private extension Data {
    nonisolated mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
