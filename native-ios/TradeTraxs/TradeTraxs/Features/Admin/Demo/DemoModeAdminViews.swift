import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DemoModeAdminView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    var body: some View {
        DemoAdminGate {
            List {
                section("Profile", "person.crop.circle", "profiles")
                section("Trading Accounts", "building.columns", "accounts")
                section("Trades", "chart.line.uptrend.xyaxis", "trades")
                section("Social", "bubble.left.and.bubble.right", "social")
                section("Activity", "bell", "activity")
                section("Messages", "message", "conversations")
                section("Trade Rooms", "person.3", "rooms")
                section("Psychology", "brain.head.profile", "psychology")
                section("Payouts", "banknote", "payouts")
                section("Vault", "archivebox", "vault")
                Section {
                    Button {
                        navigationCoordinator.pushAdmin(.demoHistory)
                    } label: {
                        SettingsNavigationRow(title: "Version History", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("admin.demo.history")
                }
            }
            .adminScreenHeading("Demo Mode")
            .experienceInsetGroupedListStyle(pageBackground: true)
            .accessibilityIdentifier("admin.demo.home")
        }
    }

    private func section(_ title: String, _ symbol: String, _ kind: String) -> some View {
        Section {
            Button {
                navigationCoordinator.pushAdmin(.demoBrowse(kind))
            } label: {
                SettingsNavigationRow(title: title, systemImage: symbol)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("admin.demo.section.\(kind)")
        }
    }
}

struct DemoAdminBrowserView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator
    let kind: String

    @State private var draft: [String: Any] = [:]
    @State private var loading = true
    @State private var error: String?
    @State private var query = ""
    @State private var accountID = ""
    @State private var social = "post"
    @State private var vault = "folder"

    var body: some View {
        DemoAdminGate {
            List {
                if kind == "social" {
                    Picker("Content", selection: $social) {
                        Text("Posts").tag("post")
                        Text("Clips").tag("clip")
                        Text("Stories").tag("story")
                        Text("Achievements").tag("achievement")
                    }
                    .pickerStyle(.segmented)
                }
                if kind == "vault" {
                    Picker("Vault", selection: $vault) {
                        Text("Folders").tag("folder")
                        Text("Items").tag("item")
                    }
                    .pickerStyle(.segmented)
                }
                if loading {
                    Text("Loading…")
                } else if let error {
                    SettingsIntroBlock(title: "Could not load Demo content", message: error)
                    Button("Try Again") { Task { await load() } }
                } else if rows.isEmpty {
                    SettingsIntroBlock(title: "Nothing here yet", message: "Create one to add it to Demo Mode.")
                } else {
                    ForEach(rows, id: \.id) { row in
                        Button {
                            open(row)
                        } label: {
                            SettingsNavigationRow(title: row.title, subtitle: row.subtitle, systemImage: nil, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .adminScreenHeading(title)
            .experienceInsetGroupedListStyle(pageBackground: true)
            .modifier(DemoTradeSearch(enabled: kind == "trades", query: $query))
            .toolbar {
                if kind == "trades" {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu(accountID.isEmpty ? "All accounts" : accountName(accountID)) {
                            Button("All accounts") { accountID = "" }
                            ForEach(accountChoices) { account in
                                Button(account.label) { accountID = account.id }
                            }
                        }
                    }
                }
                if let roomID = roomID {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Add") {
                            Button("Member") {
                                navigationCoordinator.pushAdmin(.demoEdit(entity: "membership", recordID: roomID, isNew: true))
                            }
                            Button("Message") {
                                navigationCoordinator.pushAdmin(.demoEdit(entity: "room_message", recordID: "\(roomID)|\(DemoAdminIDs.make("room_message"))", isNew: true))
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { create() }
                        .disabled(createEntity == nil)
                }
            }
            .task { await load() }
            .onAppear { Task { await load() } }
        }
    }

    private var title: String {
        switch kind {
        case "profiles": return "Profile"
        case "accounts": return "Trading Accounts"
        case "trades": return "Trades"
        case "social": return "Social"
        case "activity": return "Activity"
        case "conversations": return "Messages"
        case "rooms": return "Trade Rooms"
        case "psychology": return "Psychology"
        case "payouts": return "Payouts"
        case "vault": return "Vault"
        default:
            if kind.hasPrefix("messages/") { return "Conversation" }
            if kind.hasPrefix("room/") { return "Trade Room" }
            return "Demo"
        }
    }

    private var rows: [DemoAdminRow] {
        let all = makeRows().filter { row in
            guard kind == "trades" else { return true }
            if !accountID.isEmpty && row.accountID != accountID { return false }
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if needle.isEmpty { return true }
            return row.title.lowercased().contains(needle) || row.subtitle.lowercased().contains(needle)
        }
        return all
    }

    private var createEntity: String? {
        switch kind {
        case "profiles": return "profile"
        case "accounts": return "account"
        case "trades": return "trade"
        case "activity": return "activity"
        case "conversations": return "conversation"
        case "psychology": return "check_in"
        case "payouts": return "payout"
        case "social": return social
        case "vault": return vault == "folder" ? "vault_folder" : "vault_item"
        default:
            if kind.hasPrefix("messages/") { return "message" }
            if kind.hasPrefix("room/") { return nil }
            return nil
        }
    }

    @ViewBuilder private var socialPicker: some View { EmptyView() }

    private func makeRows() -> [DemoAdminRow] {
        switch kind {
        case "profiles":
            return DemoAdminLabels.profiles(in: draft).map { profile in
                DemoAdminRow(id: profile.id, entity: "profile", title: profile.label, subtitle: profile.role)
            }
        case "accounts":
            return DemoAdminLabels.rows(draft, "accounts").map { account in
                DemoAdminRow(id: account.string("id"), entity: "account", title: DemoAdminLabels.account(account), subtitle: "")
            }
        case "trades":
            return DemoAdminLabels.rows(draft, "trades").map { trade in
                let account = accountName(trade.string("accountID"))
                let side = trade.string("side").capitalized
                return DemoAdminRow(
                    id: trade.string("id"),
                    entity: "trade",
                    title: "\(trade.string("symbol.ticker")) · \(side) · \(DemoAdminLabels.money(trade.money("realizedPnL")))",
                    subtitle: "\(DemoAdminDates.display(trade.string("entryAt"))) · \(account)",
                    accountID: trade.string("accountID")
                )
            }
        case "social":
            return socialRows
        case "activity":
            return DemoAdminLabels.rows(draft, "activity").map { item in
                let actor = profileName(item.string("actorProfileID"))
                return DemoAdminRow(id: item.string("id"), entity: "activity", title: item.string("body").isEmpty ? item.string("title") : item.string("body"), subtitle: actor)
            }
        case "conversations":
            return DemoAdminLabels.rows(draft, "conversations").map { item in
                DemoAdminRow(id: item.string("id"), entity: "conversation", title: item.string("title").isEmpty ? "Conversation" : item.string("title"), subtitle: "")
            }
        case "rooms":
            return DemoAdminLabels.rows(draft, "rooms").map { item in
                DemoAdminRow(id: item.string("id"), entity: "room", title: item.string("name").isEmpty ? "Trade Room" : item.string("name"), subtitle: "")
            }
        case "psychology":
            return DemoAdminLabels.rows(draft, "checkIns").map { item in
                let stress = Int(item.string("stressLevel")) ?? 0
                let label = (1 ... 5).contains(stress) ? DemoAdminLabels.stress[stress - 1] : "Check-in"
                return DemoAdminRow(id: item.string("id"), entity: "check_in", title: item.string("checkInDate"), subtitle: label)
            }
        case "payouts":
            return DemoAdminLabels.rows(draft, "payouts").map { item in
                DemoAdminRow(
                    id: item.string("id"),
                    entity: "payout",
                    title: DemoAdminLabels.money(item.money("amount")),
                    subtitle: "\(DemoAdminDates.display(item.string("payoutDate"))) · \(accountName(item.string("accountID")))"
                )
            }
        case "vault":
            if vault == "folder" {
                return DemoAdminLabels.rows(draft, "vaultFolders").map { item in
                    DemoAdminRow(id: item.string("id"), entity: "vault_folder", title: item.string("name"), subtitle: "Folder")
                }
            }
            return DemoAdminLabels.rows(draft, "vaultItems").map { item in
                let ref = item.value("ref") as? [String: Any] ?? [:]
                return DemoAdminRow(id: item.string("id"), entity: "vault_item", title: DemoJSON.string(ref["contentType"]) ?? "Item", subtitle: "Saved item")
            }
        default:
            if let id = kind.split(separator: "/").last, kind.hasPrefix("messages/") {
                let conversationID = String(id)
                return DemoAdminLabels.rows(draft, "messages").filter { $0.string("conversationID") == conversationID }.map { item in
                    DemoAdminRow(id: item.string("id"), entity: "message", title: item.string("body"), subtitle: profileName(item.string("senderProfileID")))
                }
            }
            if let id = kind.split(separator: "/").last, kind.hasPrefix("room/") {
                let roomID = String(id)
                let members = DemoJSON.records(draft["memberships"]).filter { DemoJSON.string($0["roomID"]) == roomID }.map { member in
                    DemoAdminRow(
                        id: "\(roomID)|\(DemoJSON.string(member["profileID"]) ?? "")",
                        entity: "membership",
                        title: profileName(DemoJSON.string(member["profileID"]) ?? ""),
                        subtitle: (DemoJSON.string(member["role"]) ?? "member").capitalized
                    )
                }
                let messages = DemoAdminLabels.rows(draft, "roomMessages").filter { $0.string("roomID") == roomID }.map { item in
                    DemoAdminRow(id: item.string("id"), entity: "room_message", title: item.string("body"), subtitle: profileName(item.string("senderProfileID")))
                }
                return [DemoAdminRow(id: roomID, entity: "room", title: "Edit room", subtitle: "")] + members + messages
            }
            return []
        }
    }

    private var socialRows: [DemoAdminRow] {
        switch social {
        case "clip":
            return DemoAdminLabels.rows(draft, "clips").map { item in
                DemoAdminRow(id: item.string("id"), entity: "clip", title: item.string("caption"), subtitle: profileName(item.string("authorProfileID")))
            }
        case "story":
            return DemoAdminLabels.rows(draft, "stories").map { item in
                DemoAdminRow(id: item.string("id"), entity: "story", title: profileName(item.string("authorProfileID")), subtitle: DemoAdminDates.display(item.string("createdAt")))
            }
        case "achievement":
            return DemoAdminLabels.rows(draft, "achievements").map { item in
                DemoAdminRow(id: item.string("id"), entity: "achievement", title: item.string("title"), subtitle: profileName(item.string("ownerProfileID")))
            }
        default:
            return DemoAdminLabels.rows(draft, "posts").map { item in
                DemoAdminRow(id: item.string("id"), entity: "post", title: item.string("body"), subtitle: profileName(item.string("authorProfileID")))
            }
        }
    }

    private func open(_ row: DemoAdminRow) {
        if kind == "conversations" {
            navigationCoordinator.pushAdmin(.demoBrowse("messages/\(row.id)"))
            return
        }
        if kind == "rooms" {
            navigationCoordinator.pushAdmin(.demoBrowse("room/\(row.id)"))
            return
        }
        navigationCoordinator.pushAdmin(.demoEdit(entity: row.entity, recordID: row.id, isNew: false))
    }

    private func create() {
        guard let entity = createEntity else { return }
        let id: String
        if entity == "message", let conversationID = kind.split(separator: "/").last {
            id = "\(conversationID)|\(DemoAdminIDs.make("message"))"
        } else {
            id = DemoAdminIDs.make(entity)
        }
        navigationCoordinator.pushAdmin(.demoEdit(entity: entity, recordID: id, isNew: true))
    }

    private var roomID: String? {
        guard kind.hasPrefix("room/") else { return nil }
        return kind.split(separator: "/").last.map(String.init)
    }

    private var accountChoices: [DemoChoice] {
        DemoAdminLabels.rows(draft, "accounts").map { DemoChoice(id: $0.string("id"), label: DemoAdminLabels.account($0)) }
    }

    private func accountName(_ id: String) -> String {
        DemoAdminLabels.rows(draft, "accounts").first { $0.string("id") == id }.map(DemoAdminLabels.account) ?? "Account"
    }

    private func profileName(_ id: String) -> String {
        DemoAdminLabels.profiles(in: draft).first { $0.id == id }?.label ?? "Profile"
    }

    private func load() async {
        do {
            let state = try await data.demoAdminService().load()
            draft = DemoJSON.object(state.draft)
            error = nil
        } catch {
            self.error = (error as? DemoAdminError)?.message ?? "Could not load Demo content."
        }
        loading = false
    }
}

private struct DemoAdminRow: Identifiable {
    var id: String
    var entity: String
    var title: String
    var subtitle: String
    var accountID: String = ""
}

struct DemoAdminEditorView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator
    let entity: String
    let recordID: String
    let isNew: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var form = DemoObject()
    @State private var role = "peer"
    @State private var draft: [String: Any] = [:]
    @State private var ready = false
    @State private var loading = true
    @State private var saving = false
    @State private var mediaUploads = 0
    @State private var error: String?
    @State private var confirmsDelete = false
    @State private var confirmsLeave = false
    @State private var baseline = Data()

    var body: some View {
        DemoAdminGate {
            Group {
                if loading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !ready {
                    ContentUnavailableView("Missing Demo item", systemImage: "exclamationmark.triangle", description: Text(error ?? "This item is no longer in the Demo dataset."))
                } else {
                    formBody
                }
            }
            .adminScreenHeading(editorTitle)
            .toolbar {
                if dirty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { confirmsLeave = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mediaUploads > 0 ? "Uploading…" : (saving ? "Saving…" : "Save")) { Task { await save() } }
                        .disabled(saving || !ready || mediaUploads > 0)
                        .accessibilityIdentifier("admin.demo.save")
                }
            }
            .navigationBarBackButtonHidden(dirty)
            .confirmationDialog("Leave without saving?", isPresented: $confirmsLeave, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .confirmationDialog("Delete this from Demo Mode?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await remove() } }
                Button("Cancel", role: .cancel) {}
            }
            .task { await load() }
        }
    }

    private var dirty: Bool {
        canonical(form.storage) != baseline
    }

    private func canonical(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    private var editorTitle: String {
        switch entity {
        case "profile": return "Profile"
        case "account": return "Account"
        case "trade": return "Trade"
        case "post": return "Post"
        case "clip": return "Clip"
        case "story": return "Story"
        case "achievement": return "Achievement"
        case "activity": return "Activity"
        case "conversation": return "Conversation"
        case "message": return "Message"
        case "room": return "Trade Room"
        case "membership": return "Member"
        case "room_message": return "Room Message"
        case "check_in": return "Check-In"
        case "payout": return "Payout"
        case "vault_folder": return "Folder"
        case "vault_item": return "Vault Item"
        default: return "Edit"
        }
    }

    private var formBody: some View {
        Form {
            if let error {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
            fields
            if !isNew, form.string("id") != DemoAdminLabels.viewerID {
                Section {
                    Button("Delete", role: .destructive) { confirmsDelete = true }
                        .disabled(saving)
                }
            }
        }
    }

    @ViewBuilder private var fields: some View {
        switch entity {
        case "profile":
            text("Display name", "displayName")
            text("Username", "username")
            media("Avatar", "avatar", type: "profile", mediaKind: "image", objectKey: "avatar")
            area("Bio", "bio")
            choices("Trader type", "traderType", options: ["Futures", "Options", "Investor", "Forex"])
            text("Trading style", "tradingStyle")
            text("Primary market", "primaryMarket")
            if form.string("id") != DemoAdminLabels.viewerID {
                choices("Role", selection: role, options: [("peer", "Peer"), ("host", "Host")]) { role = $0 }
            }
        case "account":
            Group {
            text("Account name", "name")
            text("Account number", "accountNumber")
            choices("Mode", "mode", options: [("evaluation", "Evaluation"), ("funded", "Funded"), ("live", "Live"), ("sim", "Sim"), ("backtest", "Backtest")])
            choices("Firm / broker type", "category", options: [("propFirm", "Prop firm"), ("broker", "Broker"), ("personal", "Personal"), ("backtest", "Backtest")])
            moneyField("Starting balance", "size")
            }
        case "trade":
            Group {
            recordChoices("Account", "accountID", choices: accountChoices)
            text("Symbol", "symbol.ticker")
            choices("Side", "side", options: [("long", "Long"), ("short", "Short")])
            number("Quantity", "quantity")
            number("Entry price", "entryPrice")
            number("Exit price", "exitPrice")
            moneyField("P&L", "realizedPnL")
            dateTime("Entry", "entryAt")
            dateTime("Exit", "exitAt")
            area("Notes", "notes")
            media("Screenshot", "thumbnail", type: "trade", mediaKind: "image", objectKey: "thumbnail")
            number("Confidence (1–5)", "confidence")
            choices("Emotion", "emotion", options: DemoAdminLabels.emotions, allowsEmpty: true)
            choices("Exit emotion", "exitEmotion", options: DemoAdminLabels.emotions, allowsEmpty: true)
            choices("Followed plan", selection: planValue, options: [("", "Not set"), ("yes", "Yes"), ("no", "No")]) { value in
                form.set("followedPlan", value.isEmpty ? nil : value == "yes")
            }
            number("Execution rating (1–5)", "executionRating")
            area("Psychology notes", "psychologyNotes")
            choices("Visibility", "visibility", options: [("public", "Public"), ("followersOnly", "Followers"), ("private", "Private")])
            text("Public caption", "publicCaption")
            text("Strategy", "strategy")
            text("Session", "sessionLabel")
            }
        case "post", "clip", "story":
            Group {
            recordChoices("Author", "authorProfileID", choices: profileChoices)
            if entity != "story" { recordChoices("Trade", "linkedTradeID", choices: tradeChoices, allowsEmpty: true) }
            if entity == "post" {
                area("Caption", "body")
                media("Image", "media", type: "post", mediaKind: "image", objectKey: "media", array: true)
            }
            if entity == "clip" {
                text("Caption", "caption")
                media("Video", "video", type: "clip", mediaKind: "video", objectKey: "video")
                media("Thumbnail", "thumbnail", type: "clip", mediaKind: "image", objectKey: "thumbnail")
            }
            if entity == "story" {
                media("Story media", "media", type: "story", mediaKind: "either", objectKey: "media")
            }
            choices("Visibility", "visibility", options: [("public", "Public"), ("followersOnly", "Followers"), ("private", "Private")])
            }
        case "achievement":
            Group {
            text("Title", "title")
            recordChoices("Owner", "ownerProfileID", choices: profileChoices)
            recordChoices("Account", "accountID", choices: accountChoices, allowsEmpty: true)
            area("Description", "description")
            text("Firm", "firm")
            media("Image", "image", type: "achievement", mediaKind: "image", objectKey: "image")
            moneyField("Value", "value")
            toggle("Public", "isPublic")
            toggle("Featured", "isFeatured")
            }
        case "activity":
            Group {
            choices("Type", "kind", options: [("like", "Like"), ("comment", "Comment"), ("follow", "Follow"), ("room_mention", "Trade Room mention"), ("trading_report", "Monthly trading report"), ("system", "System")])
            if form.string("kind") != "trading_report" && form.string("kind") != "system" {
                recordChoices("Actor", "actorProfileID", choices: profileChoices)
            }
            if ["like", "comment", "system"].contains(form.string("kind")) {
                recordChoices("Trade", "tradeID", choices: tradeChoices, allowsEmpty: true)
            }
            if form.string("kind") == "room_mention" {
                recordChoices("Room", "roomID", choices: roomChoices)
            }
            area("Text", "body")
            }
        case "conversation":
            text("Title", "title")
            Section("People") {
                ForEach(profileChoices) { choice in
                    Toggle(choice.label, isOn: participantBinding(choice.id))
                }
            }
        case "message", "room_message":
            recordChoices("Sender", "senderProfileID", choices: profileChoices)
            area("Message", "body")
            recordChoices("Shared trade", entity == "room_message" ? "attachedTradeID" : "sharedTrade", choices: tradeChoices, allowsEmpty: true)
        case "room":
            text("Room name", "name")
            text("Slug", "slug")
            area("Description", "description")
            media("Image", "image", type: "room", mediaKind: "image", objectKey: "image")
            recordChoices("Owner", "ownerProfileID", choices: profileChoices)
            area("Rules", "rules")
        case "membership":
            recordChoices("Profile", "profileID", choices: profileChoices)
            choices("Role", "role", options: [("owner", "Owner"), ("admin", "Admin"), ("member", "Member")])
        case "check_in":
            dayField("Date", "checkInDate")
            number("Sleep hours", "sleepHours")
            rating("Sleep quality", "sleepQuality")
            rating("Morning rating", "morningRating")
            choices("Stress", selection: form.string("stressLevel"), options: (1 ... 5).map { ("\($0)", "\($0) · \(DemoAdminLabels.stress[$0 - 1])") }) { value in
                form.set("stressLevel", Int(value) ?? 1)
            }
            rating("Energy", "energyLevel")
            rating("Focus", "focusLevel")
            area("Notes", "notes")
        case "payout":
            recordChoices("Account", "accountID", choices: accountChoices)
            moneyField("Amount", "amount")
            dateTime("Date", "payoutDate")
            area("Note", "note")
            media("Image", "imageURL", type: "payout", mediaKind: "image", objectKey: nil)
        case "vault_folder":
            text("Folder name", "name")
        case "vault_item":
            choices("Saved item", selection: contentType, options: [("trade", "Trade"), ("feed_post", "Post"), ("reel", "Clip"), ("achievement", "Achievement")]) { value in
                form.set("ref", ["contentType": value, "contentID": ""])
            }
            recordChoices("Target", selection: contentID, choices: vaultTargets) { value in
                form.set("ref", ["contentType": contentType, "contentID": value])
            }
        default:
            EmptyView()
        }
    }

    private var planValue: String {
        switch form.bool("followedPlan") {
        case true: return "yes"
        case false: return "no"
        default: return ""
        }
    }

    private var contentType: String {
        (form.value("ref") as? [String: Any]).flatMap { DemoJSON.string($0["contentType"]) } ?? "trade"
    }

    private var contentID: String {
        (form.value("ref") as? [String: Any]).flatMap { DemoJSON.string($0["contentID"]) } ?? ""
    }

    private var vaultTargets: [DemoChoice] {
        switch contentType {
        case "reel": return clipChoices
        case "achievement": return achievementChoices
        case "feed_post": return postChoices
        default: return tradeChoices
        }
    }

    private var profileChoices: [DemoChoice] {
        DemoAdminLabels.profiles(in: draft).map { DemoChoice(id: $0.id, label: $0.label) }
    }

    private var accountChoices: [DemoChoice] {
        DemoAdminLabels.rows(draft, "accounts").map { DemoChoice(id: $0.string("id"), label: DemoAdminLabels.account($0)) }
    }

    private var tradeChoices: [DemoChoice] {
        DemoAdminLabels.rows(draft, "trades").map { trade in
            let account = accountChoices.first { $0.id == trade.string("accountID") }?.label ?? ""
            return DemoChoice(id: trade.string("id"), label: DemoAdminLabels.trade(trade, account: account))
        }
    }

    private var roomChoices: [DemoChoice] {
        DemoAdminLabels.rows(draft, "rooms").map { DemoChoice(id: $0.string("id"), label: $0.string("name")) }
    }

    private var postChoices: [DemoChoice] {
        DemoAdminLabels.rows(draft, "posts").map { DemoChoice(id: $0.string("id"), label: $0.string("body")) }
    }

    private var clipChoices: [DemoChoice] {
        DemoAdminLabels.rows(draft, "clips").map { DemoChoice(id: $0.string("id"), label: $0.string("caption")) }
    }

    private var achievementChoices: [DemoChoice] {
        DemoAdminLabels.rows(draft, "achievements").map { DemoChoice(id: $0.string("id"), label: $0.string("title")) }
    }

    private func text(_ label: String, _ path: String) -> some View {
        TextField(label, text: binding(path))
    }

    private func area(_ label: String, _ path: String) -> some View {
        TextField(label, text: binding(path), axis: .vertical)
            .lineLimit(3 ... 6)
    }

    private func number(_ label: String, _ path: String) -> some View {
        TextField(label, text: binding(path))
            .keyboardType(.decimalPad)
    }

    private func moneyField(_ label: String, _ path: String) -> some View {
        TextField(label, text: Binding(
            get: { form.money(path).map { DemoJSON.string($0 as NSNumber) ?? "\($0)" } ?? "" },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: "+", with: "")
                if trimmed.isEmpty {
                    form.set(path, nil)
                } else if let amount = Double(trimmed) {
                    let existing = form.value(path) as? [String: Any]
                    let currency = DemoJSON.string(existing?["currencyCode"]) ?? "USD"
                    form.set(path, ["amount": amount, "currencyCode": currency])
                }
            }
        ))
        .keyboardType(.decimalPad)
    }

    private func binding(_ path: String) -> Binding<String> {
        Binding(
            get: { form.string(path) },
            set: { value in
                if path == "symbol.ticker" {
                    form.set(path, value.uppercased())
                } else if path == "quantity" || path == "entryPrice" || path == "exitPrice" || path == "confidence" || path == "executionRating" || path == "sleepHours" {
                    if value.isEmpty {
                        form.set(path, nil)
                    } else if path == "quantity" || path == "confidence" || path == "executionRating", let number = Int(value) {
                        form.set(path, number)
                    } else if let number = Double(value) {
                        form.set(path, number)
                    } else {
                        form.set(path, value)
                    }
                } else {
                    form.set(path, value.isEmpty ? nil : value)
                }
            }
        )
    }

    private func choices(_ label: String, _ path: String, options: [String], allowsEmpty: Bool = false) -> some View {
        choices(label, selection: form.string(path), options: options.map { ($0, $0) }, allowsEmpty: allowsEmpty) { form.set(path, $0.isEmpty ? nil : $0) }
    }

    private func choices(_ label: String, _ path: String, options: [(String, String)], allowsEmpty: Bool = false) -> some View {
        choices(label, selection: form.string(path), options: options, allowsEmpty: allowsEmpty) { form.set(path, $0) }
    }

    private func choices(_ label: String, selection: String, options: [(String, String)], allowsEmpty: Bool = false, onSelect: @escaping (String) -> Void) -> some View {
        DemoAdminChoiceField(
            title: label,
            selection: selection,
            choices: options.map { DemoChoice(id: $0.0, label: $0.1) },
            allowsEmpty: allowsEmpty,
            onSelect: onSelect
        )
    }

    private func choices(_ label: String, selection: String, options: [String], allowsEmpty: Bool = false, onSelect: @escaping (String) -> Void) -> some View {
        choices(label, selection: selection, options: options.map { ($0, $0) }, allowsEmpty: allowsEmpty, onSelect: onSelect)
    }

    private func recordChoices(_ label: String, _ path: String, choices: [DemoChoice], allowsEmpty: Bool = false) -> some View {
        let selection = path == "sharedTrade" ? sharedTradeID : form.string(path)
        return DemoAdminChoiceField(title: label, selection: selection, choices: choices, allowsEmpty: allowsEmpty) { value in
            if path == "sharedTrade" {
                applySharedTrade(value)
            } else if path == "stressLevel" {
                form.set(path, Int(value) ?? 3)
            } else {
                form.set(path, value.isEmpty ? nil : value)
            }
        }
    }

    private func recordChoices(_ label: String, selection: String, choices: [DemoChoice], onSelect: @escaping (String) -> Void) -> some View {
        DemoAdminChoiceField(title: label, selection: selection, choices: choices, allowsEmpty: false, onSelect: onSelect)
    }

    private var sharedTradeID: String {
        let shared = form.value("sharedContent") as? [String: Any]
        let trade = shared?["trade"] as? [String: Any]
        return DemoJSON.string(trade?["_0"]) ?? ""
    }

    private func applySharedTrade(_ id: String) {
        if id.isEmpty {
            form.set("sharedContent", nil)
            form.set("kind", "text")
        } else {
            form.set("sharedContent", ["trade": ["_0": id]])
            form.set("kind", "tradeShare")
        }
    }

    private func rating(_ label: String, _ path: String) -> some View {
        choices(label, selection: form.string(path), options: (1 ... 5).map { ("\($0)", "\($0)") }) { value in
            form.set(path, Int(value) ?? 3)
        }
    }

    private func toggle(_ label: String, _ path: String) -> some View {
        Toggle(label, isOn: Binding(
            get: { form.bool(path) ?? true },
            set: { form.set(path, $0) }
        ))
    }

    private func dateTime(_ label: String, _ path: String) -> some View {
        DatePicker(label, selection: Binding(
            get: { DemoAdminDates.parse(form.string(path)) ?? Date() },
            set: { form.set(path, DemoAdminDates.iso($0)) }
        ), displayedComponents: [.date, .hourAndMinute])
    }

    private func dayField(_ label: String, _ path: String) -> some View {
        DatePicker(label, selection: Binding(
            get: { DemoAdminDates.parse(form.string(path)) ?? Date() },
            set: { form.set(path, DemoAdminDates.day($0)) }
        ), displayedComponents: [.date])
    }

    private func media(_ label: String, _ path: String, type: String, mediaKind: String, objectKey: String?, array: Bool = false) -> some View {
        DemoAdminMediaField(
            title: label,
            url: mediaURL(path, array: array, objectKey: objectKey),
            entityType: type,
            entityId: form.string("id"),
            kind: mediaKind,
            service: data.demoAdminService(),
            onCommit: { url, pickedKind in
                DemoAdminMediaAssignment.apply(
                    form: &form,
                    path: path,
                    objectKey: objectKey,
                    url: url,
                    kind: pickedKind,
                    array: array
                )
            },
            onBusy: { busy in
                mediaUploads = max(0, mediaUploads + (busy ? 1 : -1))
            },
            onError: { message in
                error = message
            }
        )
    }

    private func mediaURL(_ path: String, array: Bool, objectKey: String?) -> String {
        if path == "imageURL" { return form.string(path) }
        let key = objectKey ?? path
        let value = array ? (form.value(key) as? [Any])?.first : form.value(key)
        if let object = value as? [String: Any] { return DemoJSON.string(object["id"]) ?? "" }
        return DemoJSON.string(value) ?? ""
    }

    private func participantBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: {
                let ids = form.value("participantProfileIDs") as? [Any] ?? []
                return ids.contains { DemoJSON.string($0) == id }
            },
            set: { included in
                var ids = (form.value("participantProfileIDs") as? [Any] ?? []).compactMap { DemoJSON.string($0) }
                if included, !ids.contains(id) { ids.append(id) }
                if !included { ids.removeAll { $0 == id } }
                form.set("participantProfileIDs", ids)
            }
        )
    }

    private func load() async {
        do {
            let state = try await data.demoAdminService().load()
            draft = DemoJSON.object(state.draft)
            if isNew {
                form = DemoAdminBlank.make(entity: entity, recordID: recordID, draft: draft)
                role = "peer"
            } else if let existing = DemoAdminBlank.find(entity: entity, recordID: recordID, draft: draft) {
                form = existing.record
                role = existing.role
            } else {
                ready = false
                loading = false
                return
            }
            baseline = canonical(form.storage)
            ready = true
            error = nil
        } catch {
            self.error = (error as? DemoAdminError)?.message ?? "Could not load Demo content."
            ready = false
        }
        loading = false
    }

    private func save() async {
        if mediaUploads > 0 {
            error = "Wait for the image upload to finish before saving."
            return
        }
        saving = true
        error = nil
        var record = form
        if entity == "activity" {
            if record.string("tradeID").isEmpty { record.set("tradeID", nil) }
            if record.value("isReply") == nil { record.set("isReply", false) }
            if record.value("isMention") == nil { record.set("isMention", false) }
            if record.value("isRead") == nil { record.set("isRead", false) }
        }
        if entity == "trade" {
            let notes = record.string("notes")
            record.set("notePreview", notes.isEmpty ? nil : notes)
            record.set("updatedAt", DemoAdminDates.iso(Date()))
        }
        if entity == "room" {
            let name = record.string("name")
            if record.string("slug").isEmpty {
                record.set("slug", name.lowercased().replacingOccurrences(of: " ", with: "-"))
            }
        }
        do {
            _ = try await data.demoAdminService().saveAndPublish(
                entity: entity,
                record: record.jsonObject(),
                role: entity == "profile" ? (record.string("id") == DemoAdminLabels.viewerID ? "viewer" : role) : nil
            )
            dismiss()
        } catch {
            self.error = humanized(error)
        }
        saving = false
    }

    private func remove() async {
        saving = true
        do {
            if entity == "membership" {
                _ = try await data.demoAdminService().deleteAndPublish(
                    entity: entity,
                    id: "",
                    roomID: form.string("roomID"),
                    profileID: form.string("profileID")
                )
            } else {
                _ = try await data.demoAdminService().deleteAndPublish(entity: entity, id: form.string("id"))
            }
            dismiss()
        } catch {
            self.error = humanized(error)
        }
        saving = false
    }

    private func humanized(_ error: Error) -> String {
        guard let demo = error as? DemoAdminError else { return "Could not update Demo Mode." }
        switch demo {
        case .validation(let issues):
            return issues.map { DemoAdminLabels.humanize($0, draft: draft) }.joined(separator: "\n")
        default:
            return DemoAdminLabels.humanize(demo.message, draft: draft)
        }
    }
}

struct DemoAdminHistoryView: View {
    let data: DataEnvironment

    @State private var versions: [DemoAdminVersion] = []
    @State private var loading = true
    @State private var error: String?
    @State private var pending: DemoAdminVersion?
    @State private var notice: String?

    var body: some View {
        DemoAdminGate {
            List {
                if loading {
                    Text("Loading…")
                } else if let error {
                    SettingsIntroBlock(title: "Could not load versions", message: error)
                    Button("Try Again") { Task { await load() } }
                } else {
                    if let notice {
                        Text(notice)
                    }
                    ForEach(versions) { version in
                        Button {
                            pending = version.isCurrent ? nil : version
                        } label: {
                            SettingsNavigationRow(
                                title: "Version \(version.version)",
                                subtitle: version.isCurrent ? "Current" : DemoAdminDates.display(version.publishedAt ?? ""),
                                systemImage: nil,
                                showsChevron: !version.isCurrent
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(version.isCurrent)
                        .accessibilityIdentifier("admin.demo.version.\(version.version)")
                    }
                }
            }
            .adminScreenHeading("Version History")
            .experienceInsetGroupedListStyle(pageBackground: true)
            .confirmationDialog(
                "Restore version \(pending?.version ?? 0)?",
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                titleVisibility: .visible
            ) {
                Button("Restore") { Task { await restore() } }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                Text("This publishes that Demo dataset again. Explore as Guest will use it the next time you enter Demo Mode.")
            }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            let state = try await data.demoAdminService().load()
            versions = state.history.sorted { $0.version > $1.version }
            error = nil
        } catch {
            self.error = (error as? DemoAdminError)?.message ?? "Could not load versions."
        }
        loading = false
    }

    private func restore() async {
        guard let version = pending else { return }
        pending = nil
        do {
            let state = try await data.demoAdminService().restore(version: version.version)
            versions = state.history.sorted { $0.version > $1.version }
            notice = "Restored. Demo Mode will show this the next time you enter it."
        } catch {
            self.error = (error as? DemoAdminError)?.message ?? "Could not restore that version."
        }
    }
}

private struct DemoTradeSearch: ViewModifier {
    var enabled: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $query, prompt: "Symbol or account")
        } else {
            content
        }
    }
}

private struct DemoAdminGate<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var allowed = DemoAdminEntry.isAvailable(isPlatformAdmin: SessionBootstrapStore.shared.isPlatformAdmin)

    var body: some View {
        Group {
            if allowed {
                content()
            } else {
                List {
                    Section {
                        SettingsIntroBlock(
                            title: "Admin access is required.",
                            message: "Demo Mode editing is limited to TradeTraxs platform admins."
                        )
                    }
                }
                .experienceInsetGroupedListStyle(pageBackground: true)
                .accessibilityIdentifier("admin.demo.denied")
            }
        }
        .onAppear {
            allowed = DemoAdminEntry.isAvailable(isPlatformAdmin: SessionBootstrapStore.shared.isPlatformAdmin)
        }
    }
}

private struct DemoChoice: Identifiable, Hashable {
    var id: String
    var label: String
}

private struct DemoAdminChoiceField: View {
    let title: String
    let selection: String
    let choices: [DemoChoice]
    var allowsEmpty: Bool = false
    let onSelect: (String) -> Void
    @State private var open = false
    @State private var query = ""

    var body: some View {
        Button {
            open = true
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(currentLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .sheet(isPresented: $open) {
            NavigationStack {
                List {
                    if allowsEmpty {
                        Button("None") {
                            onSelect("")
                            open = false
                        }
                    }
                    ForEach(filtered) { choice in
                        Button(choice.label) {
                            onSelect(choice.id)
                            open = false
                        }
                    }
                }
                .navigationTitle(title)
                .searchable(text: $query)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { open = false }
                    }
                }
            }
        }
    }

    private var currentLabel: String {
        if selection.isEmpty { return allowsEmpty ? "None" : "Select" }
        return choices.first { $0.id == selection }?.label ?? "Select"
    }

    private var filtered: [DemoChoice] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return choices }
        return choices.filter { $0.label.lowercased().contains(needle) || $0.id == selection }
    }
}

private struct DemoAdminMediaField: View {
    let title: String
    let url: String
    let entityType: String
    let entityId: String
    let kind: String
    let service: DemoAdminService
    let onCommit: (String, String) -> Void
    let onBusy: (Bool) -> Void
    let onError: (String?) -> Void

    @State private var photo: PhotosPickerItem?
    @State private var video: PhotosPickerItem?
    @State private var uploading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            if kind != "video", let imageURL = URL(string: url), !url.isEmpty {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .frame(maxHeight: 160)
            } else if !url.isEmpty {
                Text("Video attached")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if uploading {
                ProgressView("Uploading…")
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            HStack {
                if kind != "video" {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Text(url.isEmpty ? "Upload" : "Replace")
                    }
                }
                if kind != "image" {
                    PhotosPicker(selection: $video, matching: .videos) {
                        Text(kind == "either" ? "Replace Video" : (url.isEmpty ? "Upload" : "Replace"))
                    }
                }
                if !url.isEmpty {
                    Button("Remove", role: .destructive) {
                        onCommit("", kind == "video" ? "video" : "image")
                        error = nil
                        onError(nil)
                    }
                }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await uploadImage(item) }
        }
        .onChange(of: video) { _, item in
            guard let item else { return }
            Task { await uploadVideo(item) }
        }
    }

    private func uploadImage(_ item: PhotosPickerItem) async {
        uploading = true
        onBusy(true)
        error = nil
        onError(nil)
        let previous = url
        defer {
            uploading = false
            onBusy(false)
            photo = nil
        }
        do {
            guard let picked = try await item.loadTransferable(type: DemoPickedImage.self),
                  let image = UIImage(data: picked.data),
                  let jpeg = image.jpegData(compressionQuality: 0.9)
            else {
                throw DemoAdminError.failed("That image could not be read. The current Demo media was left unchanged.")
            }
            let uploaded = try await service.uploadMedia(
                data: jpeg,
                mime: "image/jpeg",
                filename: "image.jpg",
                entityType: entityType,
                entityId: entityId,
                kind: "image"
            )
            onCommit(uploaded, "image")
        } catch {
            onCommit(previous, "image")
            let message = DemoAdminService.friendly(error)
            self.error = message
            onError(message)
        }
    }

    private func uploadVideo(_ item: PhotosPickerItem) async {
        uploading = true
        onBusy(true)
        error = nil
        onError(nil)
        let previous = url
        defer {
            uploading = false
            onBusy(false)
            video = nil
        }
        do {
            guard let picked = try await item.loadTransferable(type: DemoPickedVideo.self) else {
                throw DemoAdminError.failed("That video could not be read. The current Demo media was left unchanged.")
            }
            let uploaded = try await service.uploadMedia(
                data: picked.data,
                mime: picked.mime,
                filename: picked.filename,
                entityType: entityType,
                entityId: entityId,
                kind: "video"
            )
            onCommit(uploaded, "video")
        } catch {
            onCommit(previous, "video")
            let message = DemoAdminService.friendly(error)
            self.error = message
            onError(message)
        }
    }
}

private nonisolated struct DemoPickedImage: Transferable {
    var data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            DemoPickedImage(data: data)
        }
    }
}

private nonisolated struct DemoPickedVideo: Transferable {
    var data: Data
    var filename: String
    var mime: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let data = try Data(contentsOf: received.file)
            let ext = received.file.pathExtension.lowercased()
            let mime = ext == "mov" ? "video/quicktime" : "video/mp4"
            return DemoPickedVideo(data: data, filename: "video.\(ext.isEmpty ? "mp4" : ext)", mime: mime)
        }
    }
}

private nonisolated enum DemoAdminIDs {
    static func make(_ prefix: String) -> String {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        return "demo.\(prefix).\(token)"
    }
}

private nonisolated enum DemoAdminDates {
    static func parse(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return date }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(secondsFromGMT: 0)
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: String(value.prefix(10)))
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func display(_ value: String) -> String {
        guard let date = parse(value) else { return String(value.prefix(10)) }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private nonisolated enum DemoAdminBlank {
    static func make(entity: String, recordID: String, draft: [String: Any]) -> DemoObject {
        let now = DemoAdminDates.iso(Date())
        let accountID = DemoAdminLabels.rows(draft, "accounts").first?.string("id") ?? ""
        let profileID = DemoAdminLabels.profiles(in: draft).first?.id ?? DemoAdminLabels.viewerID
        switch entity {
        case "profile":
            let username = recordID.replacingOccurrences(of: ".", with: "")
            return DemoObject([
                "id": recordID, "userID": recordID, "displayName": "New trader", "username": username,
                "bio": "", "traderType": "Futures", "tradingStyle": "", "isPrivate": false, "createdAt": now,
            ])
        case "account":
            return DemoObject([
                "id": recordID, "ownerProfileID": DemoAdminLabels.viewerID, "name": "New account",
                "mode": "evaluation", "category": "propFirm", "isActive": true, "showInAccountDropdowns": true,
                "size": ["amount": 50000, "currencyCode": "USD"],
            ])
        case "trade":
            return DemoObject([
                "id": recordID, "ownerProfileID": DemoAdminLabels.viewerID, "accountID": accountID,
                "symbol": ["ticker": "NQ"], "side": "long", "mode": "sim", "quantity": 1,
                "entryPrice": 0, "exitPrice": 0, "entryAt": now, "exitAt": now,
                "realizedPnL": ["amount": 0, "currencyCode": "USD"], "visibility": "public",
                "imageDisplayMode": "fit", "createdAt": now, "updatedAt": now,
            ])
        case "membership":
            return DemoObject(["roomID": recordID, "profileID": "", "role": "member"])
        case "room_message":
            let roomParts = recordID.split(separator: "|", maxSplits: 1).map(String.init)
            return DemoObject([
                "id": roomParts.count > 1 ? roomParts[1] : recordID,
                "roomID": roomParts.first ?? "",
                "senderProfileID": profileID,
                "body": "",
                "createdAt": now,
            ])
        case "message":
            let parts = recordID.split(separator: "|", maxSplits: 1).map(String.init)
            return DemoObject([
                "id": parts.count > 1 ? parts[1] : recordID,
                "conversationID": parts.first ?? "",
                "senderProfileID": profileID,
                "body": "",
                "kind": "text",
                "attachments": [Any](),
                "roomReactions": [Any](),
                "isReadByViewer": true,
                "createdAt": now,
            ])
        case "check_in":
            return DemoObject([
                "id": recordID, "ownerProfileID": DemoAdminLabels.viewerID, "checkInDate": DemoAdminDates.day(Date()),
                "sleepHours": 7, "sleepQuality": 3, "morningRating": 3, "stressLevel": 1,
                "energyLevel": 3, "focusLevel": 3, "notes": "",
            ])
        case "payout":
            return DemoObject([
                "id": recordID, "accountID": accountID, "amount": ["amount": 0, "currencyCode": "USD"],
                "payoutDate": now, "note": "",
            ])
        case "vault_folder":
            return DemoObject(["id": recordID, "name": "New folder"])
        case "vault_item":
            return DemoObject(["id": recordID, "ref": ["contentType": "trade", "contentID": ""], "folderIDs": []])
        case "activity":
            return DemoObject([
                "id": recordID, "kind": "like", "actorProfileID": profileID, "title": "like",
                "body": "", "createdAt": now, "isReply": false, "isMention": false, "isRead": false,
            ])
        case "conversation":
            return DemoObject([
                "id": recordID, "title": "New conversation", "participantProfileIDs": [profileID],
                "isGroup": false, "isPinned": false, "unreadCount": 0, "isMuted": false, "updatedAt": now,
            ])
        case "post":
            return DemoObject(["id": recordID, "authorProfileID": profileID, "body": "", "visibility": "public", "createdAt": now, "media": []])
        case "clip":
            return DemoObject(["id": recordID, "authorProfileID": profileID, "caption": "", "visibility": "public", "createdAt": now])
        case "story":
            return DemoObject(["id": recordID, "authorProfileID": profileID, "visibility": "public", "createdAt": now])
        case "achievement":
            return DemoObject(["id": recordID, "ownerProfileID": profileID, "title": "Achievement", "isPublic": true, "achievedAt": now])
        default:
            return DemoObject(["id": recordID])
        }
    }

    static func find(entity: String, recordID: String, draft: [String: Any]) -> (record: DemoObject, role: String)? {
        if entity == "profile" {
            return DemoAdminLabels.profiles(in: draft).first { $0.id == recordID }.map { ($0.record, $0.role) }
        }
        if entity == "membership" {
            let parts = recordID.split(separator: "|").map(String.init)
            guard parts.count == 2 else { return nil }
            let match = DemoJSON.records(draft["memberships"]).first {
                DemoJSON.string($0["roomID"]) == parts[0] && DemoJSON.string($0["profileID"]) == parts[1]
            }
            return match.map { (DemoObject($0), "member") }
        }
        let key: String
        switch entity {
        case "account": key = "accounts"
        case "trade": key = "trades"
        case "post": key = "posts"
        case "clip": key = "clips"
        case "story": key = "stories"
        case "achievement": key = "achievements"
        case "activity": key = "activity"
        case "conversation": key = "conversations"
        case "message": key = "messages"
        case "room": key = "rooms"
        case "room_message": key = "roomMessages"
        case "check_in": key = "checkIns"
        case "payout": key = "payouts"
        case "vault_folder": key = "vaultFolders"
        case "vault_item": key = "vaultItems"
        default: return nil
        }
        return DemoAdminLabels.rows(draft, key).first { $0.string("id") == recordID }.map { ($0, "peer") }
    }
}
