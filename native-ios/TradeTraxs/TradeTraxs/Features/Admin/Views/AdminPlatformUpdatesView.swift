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
    @State private var editingID: String?
    @State private var errorMessage: String?
    @State private var confirmPublish = false
    @State private var confirmDelete = false
    @State private var deleteTarget: AdminPlatformUpdateRow?
    @State private var isBusy = false
    @State private var isLoadingInitial = true

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

                Button(isBusy ? "Saving…" : "Save Draft") {
                    Task { await saveDraft() }
                }
                .disabled(isBusy || !composerValid)

                Button(isBusy ? "Working…" : (sendPush ? "Publish & Send" : "Publish Now")) {
                    confirmPublish = true
                }
                .disabled(isBusy || !composerValid)

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
            draftsSection
            publishedSection
        }
        .adminScreenHeading("Updates")
        .experienceInsetGroupedListStyle(pageBackground: true)
        .scrollDismissesKeyboard(.interactively)
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
        .confirmationDialog(
            "Delete Update?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Update", role: .destructive) {
                guard let deleteTarget else { return }
                Task { await deleteUpdate(deleteTarget) }
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            if deleteTarget?.status == "draft" {
                Text("This draft will be permanently deleted.")
            } else {
                Text(
                    "This will permanently remove this announcement from What's New for all users."
                )
            }
        }
        .overlay {
            if isLoadingInitial && rows.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await reload() }
        .accessibilityIdentifier("admin.updates")
    }

    @ViewBuilder
    private var draftsSection: some View {
        let items = rows.filter { $0.status == "draft" }
        if !items.isEmpty {
            Section("Drafts") {
                ForEach(items) { row in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title).font(.headline)
                            Button("Edit") { loadEditor(row) }
                        }
                        Spacer(minLength: 8)
                        Button("Delete", role: .destructive) {
                            requestDelete(row)
                        }
                        .font(.subheadline)
                        .disabled(isBusy)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var publishedSection: some View {
        let items = rows.filter { $0.status == "published" }
        if !items.isEmpty {
            Section("Published") {
                ForEach(items) { row in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title).font(.headline)
                            if let b = row.broadcast, row.sendPush {
                                Text("Push: \(b.status) · ok \(b.successCount) · fail \(b.failedCount)")
                                    .font(.caption)
                                    .foregroundStyle(colors.secondaryText)
                            }
                        }
                        Spacer(minLength: 8)
                        Button("Delete", role: .destructive) {
                            requestDelete(row)
                        }
                        .font(.subheadline)
                        .disabled(isBusy)
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
    }

    private func loadEditor(_ row: AdminPlatformUpdateRow) {
        editingID = row.id
        title = row.title
        bodyText = row.body
        category = row.category
        destination = row.destination
        sendPush = row.sendPush
    }

    private func reload() async {
        guard let transport = data.supabase.transport else {
            isLoadingInitial = false
            errorMessage = "Unable to load updates. Please try again."
            return
        }
        do {
            rows = try await AdminPlatformUpdatesClient.fetchAll(transport: transport)
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
        isLoadingInitial = false
    }

    private func draftPayload() -> [String: Any] {
        [
            "title": title,
            "body": bodyText,
            "category": category,
            "destination": destination,
            "sendPush": sendPush,
        ]
    }

    private func persistDraft() async throws -> String {
        guard let transport = data.supabase.transport else {
            throw AppError.unknown(message: "Not connected.")
        }
        if let editingID {
            try await AdminPlatformUpdatesClient.patch(
                transport: transport,
                id: editingID,
                body: draftPayload()
            )
            return editingID
        }
        let created = try await AdminPlatformUpdatesClient.create(
            transport: transport,
            body: draftPayload()
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
            errorMessage = UserFacingError.message(for: error)
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
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func requestDelete(_ row: AdminPlatformUpdateRow) {
        deleteTarget = row
        confirmDelete = true
    }

    private func deleteUpdate(_ row: AdminPlatformUpdateRow) async {
        guard let transport = data.supabase.transport else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            try await AdminPlatformUpdatesClient.delete(transport: transport, id: row.id)
            rows.removeAll { $0.id == row.id }
            if editingID == row.id {
                clearComposer()
            }
            deleteTarget = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

