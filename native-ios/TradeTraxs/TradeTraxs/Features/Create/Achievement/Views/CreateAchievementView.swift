import PhotosUI
import SwiftUI
import UIKit

/// Native Create Achievement — mirrors web `AchievementUploadModal` required fields.
struct CreateAchievementView: View {
    @State private var viewModel: CreateAchievementViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var showsDiscardConfirm = false
    @State private var didApplyScreenshotPrefill = false

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        onDismiss: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: CreateAchievementViewModel(
                achievements: data.achievements,
                trades: data.trades,
                session: data.session,
                uploadService: data.uploadService,
                objectStorage: data.objectStorage,
                onDismiss: onDismiss
            )
        )
    }

    init(viewModel: CreateAchievementViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle:
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ExperienceErrorState(
                    title: "Couldn't open New Achievement",
                    message: message,
                    onRetry: { viewModel.retryLoad() }
                )
            case .ready, .publishing:
                formContent
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("New Achievement")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { requestDismiss() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.phase == .ready || viewModel.phase == .publishing {
                publishBar
            }
        }
        .confirmationDialog(
            "Discard this achievement?",
            isPresented: $showsDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { viewModel.dismissRequested() }
            Button("Keep Editing", role: .cancel) {}
        }
        .experienceSwipeToDismiss { requestDismiss() }
        .interactiveDismissDisabled()
        .task { viewModel.loadIfNeeded() }
        .onChange(of: viewModel.phase) { _, phase in
            #if DEBUG
            if phase == .ready { applyScreenshotPrefillIfNeeded() }
            #endif
        }
        .onChange(of: photoItem) { _, item in
            Task { await loadPhoto(item) }
        }
        .accessibilityIdentifier("createAchievement.root")
    }

    private var formContent: some View {
        Form {
            Section {
                NavigationLink {
                    kindPicker
                } label: {
                    SettingsNavigationRow(
                        title: "Type",
                        subtitle: viewModel.kindTitle,
                        systemImage: "trophy"
                    )
                }
            } header: {
                Text("Achievement")
            }

            Section("Details") {
                TextField("Title", text: $viewModel.titleText)
                    .accessibilityIdentifier("createAchievement.title")
                TextField("Description (optional)", text: $viewModel.descriptionText, axis: .vertical)
                    .lineLimit(3...6)
                DatePicker("Achieved", selection: $viewModel.achievedAt, displayedComponents: [.date, .hourAndMinute])
                Toggle("Public", isOn: $viewModel.isPublic)
            }

            if viewModel.isPayoutKind {
                Section("Payout") {
                    TextField("Payout Amount ($)", text: $viewModel.payoutAmountText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("createAchievement.payout")
                }
            }

            Section {
                accountPicker
            } header: {
                Text("Trading Account")
            } footer: {
                Text("Optional — link an account when it applies.")
            }
            .onAppear { viewModel.loadAccountsIfNeeded() }

            Section("Image") {
                if let preview = viewModel.imagePreview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                        .accessibilityLabel("Achievement image preview")
                    Button("Remove Image", role: .destructive) {
                        viewModel.clearImage()
                        photoItem = nil
                    }
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(imagePickerTitle, systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("createAchievement.media.picker")
            }

            if let formError = viewModel.formError {
                Section {
                    Text(formError)
                        .foregroundStyle(colors.loss)
                        .font(.footnote)
                        .accessibilityIdentifier("createAchievement.formError")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .disabled(viewModel.phase == .publishing)
    }

    private var kindPicker: some View {
        List {
            ForEach(CreateAchievementViewModel.allKinds, id: \.self) { kind in
                Button {
                    viewModel.selectKind(kind)
                } label: {
                    HStack(spacing: ExperienceSpacing.sm) {
                        Text(CreateAchievementViewModel.displayTitle(for: kind))
                            .experienceStyle(.body, color: colors.primaryText)
                        Spacer()
                        if viewModel.kind == kind {
                            Image(systemName: "checkmark")
                                .foregroundStyle(colors.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .experienceNavigationTitle("Achievement Type")
        .accessibilityIdentifier("createAchievement.kindPicker")
    }

    private var accountPicker: some View {
        Group {
            if viewModel.isLoadingAccounts && viewModel.accounts.isEmpty {
                HStack {
                    ProgressView()
                    Text("Loading accounts…")
                        .foregroundStyle(colors.secondaryText)
                }
            } else {
                Picker("Account", selection: Binding(
                    get: { viewModel.selectedAccountID?.rawValue ?? "" },
                    set: { raw in
                        viewModel.selectAccount(raw.isEmpty ? nil : TradingAccountID(raw))
                    }
                )) {
                    Text("None").tag("")
                    ForEach(viewModel.accounts) { account in
                        Text(accountLabel(account)).tag(account.id.rawValue)
                    }
                }
                .accessibilityIdentifier("createAchievement.account")
            }
        }
    }

    private func accountLabel(_ account: TradingAccount) -> String {
        var parts = [account.name]
        if account.isPropFirmAccount {
            parts.append(account.mode.rawValue.capitalized)
        }
        return parts.joined(separator: " · ")
    }

    private var imagePickerTitle: String {
        viewModel.imagePreview == nil ? "Add Image" : "Replace Image"
    }

    private var publishBar: some View {
        VStack(spacing: 0) {
            Divider()
            ExperienceButton(
                title: viewModel.phase == .publishing
                    ? (viewModel.isUploadingMedia ? "Uploading…" : "Publishing…")
                    : "Publish",
                kind: .primary,
                isEnabled: viewModel.canPublish && viewModel.phase != .publishing,
                isLoading: viewModel.phase == .publishing,
                accessibilityIdentifier: "createAchievement.publish"
            ) {
                viewModel.publish()
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
            .background(colors.backgroundPrimary.opacity(0.96))
        }
    }

    private func requestDismiss() {
        if viewModel.hasUnsavedChanges {
            showsDiscardConfirm = true
        } else {
            viewModel.dismissRequested()
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data)
        {
            viewModel.setImage(image)
        }
    }

    #if DEBUG
    private func applyScreenshotPrefillIfNeeded() {
        guard !didApplyScreenshotPrefill else { return }
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitesting-create-achievement-filled") else { return }
        didApplyScreenshotPrefill = true
        viewModel.selectKind(.propFirmPayout)
        viewModel.titleText = "First Apex payout"
        viewModel.descriptionText = "Hit consistency and booked the withdrawal."
        viewModel.payoutAmountText = "2500"
        viewModel.applyScreenshotImageFixture()
    }
    #endif
}
