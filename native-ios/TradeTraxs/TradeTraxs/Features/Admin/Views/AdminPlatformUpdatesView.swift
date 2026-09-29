import SwiftUI

struct AdminPlatformUpdatesView: View {
    let data: DataEnvironment

    @Environment(\.themeColors) private var colors
    @State private var rows: [AdminPlatformUpdateRow] = []
    @State private var title = ""
    @State private var bodyText = ""
    @State private var category = "announcement"
    @State private var destination = "whats_new"
    @State private var sendPush = false
    @State private var scheduleLater = false
    @State private var scheduleDate = Date().addingTimeInterval(3600)
    @State private var editingID: String?
    @State private var errorMessage: String?
    @State private var confirmPublish = false
    @State private var isBusy = false

    private let categories = [
        "announcement", "new_feature", "improvement", "fix", "maintenance",
    ]
    private let destinations = [
        "whats_new", "dashboard", "feed", "trades", "calendar", "analytics",
        "profile", "messages", "trade_rooms", "broker_integrations", "subscription", "settings",
    ]

    private var composerValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !bodyText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        List {
            Section("Composer") {
                TextField("Title", text: $title)
                TextField("Body", text: $bodyText, axis: .vertical)
                    .lineLimit(4 ... 8)
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                }
                Picker("Opens To", selection: $destination) {
                    ForEach(destinations, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                }
                Toggle("Send push to all devices", isOn: $sendPush)
                Toggle("Schedule", isOn: $scheduleLater)
                if scheduleLater {
                    DatePicker("Publish at", selection: $scheduleDate)
                }

                Button(isBusy ? "Saving…" : "Save Draft") {
                    Task { await saveDraft() }
                }
                .disabled(isBusy || !composerValid || scheduleLater)

                if scheduleLater {
                    Button(isBusy ? "Scheduling…" : "Schedule Update") {
                        Task { await saveScheduled() }
                    }
                    .disabled(isBusy || !composerValid)
                } else {
                    Button(isBusy ? "Working…" : (sendPush ? "Publish & Send" : "Publish Now")) {
                        confirmPublish = true
                    }
                    .disabled(isBusy || !composerValid)
                }

                if editingID != nil {
                    Button("Clear composer") {
                        clearComposer()
                    }
                    .foregroundStyle(colors.secondaryText)
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(colors.error)
                }
            }
            section("Upcoming Alerts", filter: "scheduled")
            section("Drafts", filter: "draft")
            section("Published", filter: "published")
        }
        .adminScreenHeading("Updates")
        .experienceInsetGroupedListStyle(pageBackground: true)
        .confirmationDialog(
            sendPush
                ? "Publish this update and send a push notification to all TradeTraxs users?"
                : "Publish this update?",
            isPresented: $confirmPublish,
            titleVisibility: .visible
        ) {
            Button(sendPush ? "Publish & Send" : "Publish", role: .destructive) {
                Task { await publishNow() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task { await reload() }
        .accessibilityIdentifier("admin.updates")
    }

    @ViewBuilder
    private func section(_ title: String, filter: String) -> some View {
        let items = rows.filter { $0.status == filter }
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title).font(.headline)
                        if filter == "scheduled", let iso = row.publishAt,
                           let date = PlatformUpdateDateFormat.date(from: iso) {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(colors.secondaryText)
                        }
                        if filter == "published", let b = row.broadcast, row.sendPush {
                            Text("Push: \(b.status) · ok \(b.successCount) · fail \(b.failedCount)")
                                .font(.caption)
                                .foregroundStyle(colors.secondaryText)
                        }
                        if filter != "published" {
                            Button("Edit") { loadEditor(row) }
                        }
                    }
                }
            }
        }
    }

    private func clearComposer() {
        editingID = nil
        title = ""
        bodyText = ""
        category = "announcement"
        destination = "whats_new"
        sendPush = false
        scheduleLater = false
        scheduleDate = Date().addingTimeInterval(3600)
    }

    private func loadEditor(_ row: AdminPlatformUpdateRow) {
        editingID = row.id
        title = row.title
        bodyText = row.body
        category = row.category
        destination = row.destination
        sendPush = row.sendPush
        scheduleLater = row.status == "scheduled"
        if let iso = row.publishAt, let date = PlatformUpdateDateFormat.date(from: iso) {
            scheduleDate = date
        }
    }

    private func reload() async {
        guard let transport = data.supabase.transport else { return }
        do {
            rows = try await AdminPlatformUpdatesClient.fetchAll(transport: transport)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func payload(status: String) -> [String: Any] {
        var body: [String: Any] = [
            "title": title,
            "body": bodyText,
            "category": category,
            "destination": destination,
            "sendPush": sendPush,
            "status": status,
        ]
        if status == "scheduled" {
            body["publishAt"] = PlatformUpdateDateFormat.string(from: scheduleDate)
        } else {
            body["publishAt"] = NSNull()
        }
        return body
    }

    private func persistDraft() async throws -> String {
        guard let transport = data.supabase.transport else {
            throw AppError.unknown(message: "Not connected.")
        }
        if let editingID {
            try await AdminPlatformUpdatesClient.patch(
                transport: transport,
                id: editingID,
                body: payload(status: "draft")
            )
            return editingID
        }
        let created = try await AdminPlatformUpdatesClient.create(
            transport: transport,
            body: payload(status: "draft")
        )
        editingID = created.id
        return created.id
    }

    private func saveDraft() async {
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            _ = try await persistDraft()
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveScheduled() async {
        guard let transport = data.supabase.transport else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            if let editingID {
                try await AdminPlatformUpdatesClient.patch(
                    transport: transport,
                    id: editingID,
                    body: payload(status: "scheduled")
                )
            } else {
                let created = try await AdminPlatformUpdatesClient.create(
                    transport: transport,
                    body: payload(status: "scheduled")
                )
                self.editingID = created.id
            }
            clearComposer()
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func publishNow() async {
        guard let transport = data.supabase.transport else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            let id = try await persistDraft()
            try await AdminPlatformUpdatesClient.publish(transport: transport, id: id)
            clearComposer()
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum PlatformUpdateDateFormat {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: string) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
