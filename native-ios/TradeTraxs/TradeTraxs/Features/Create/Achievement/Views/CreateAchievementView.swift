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
    @Environment(\.themeEnvironment) private var themeEnvironment
    @FocusState private var focusedField: ComposerField?

    private enum ComposerField: Hashable {
        case title
        case payout
    }

    private var usesTradeTraxsFormSurfaces: Bool {
        themeEnvironment.identifier == .tradeTraxs
    }

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
                    title: "Couldn't open Add Achievement",
                    message: message,
                    onRetry: { viewModel.retryLoad() }
                )
            case .ready, .publishing:
                composerContent
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Add Achievement")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back", action: requestDismiss)
                    .font(.body.weight(.regular))
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

    private var composerContent: some View {
        Form {
            Section {
                accountField
                    .tradeTraxsFormRowBackground(active: usesTradeTraxsFormSurfaces, layer: .input, colors: colors)
                kindField
                    .tradeTraxsFormRowBackground(active: usesTradeTraxsFormSurfaces, layer: .input, colors: colors)
                TextField("What did you achieve?", text: $viewModel.titleText)
                    .textInputAutocapitalization(.sentences)
                    .focused($focusedField, equals: .title)
                    .accessibilityIdentifier("createAchievement.title")
                    .tradeTraxsFormRowBackground(active: usesTradeTraxsFormSurfaces, layer: .input, colors: colors)
                TextField("Optional description", text: $viewModel.descriptionText, axis: .vertical)
                    .lineLimit(3...6)
                    .textInputAutocapitalization(.sentences)
                    .tradeTraxsFormRowBackground(active: usesTradeTraxsFormSurfaces, layer: .input, colors: colors)
            } header: {
                sectionHeader("Achievement Details")
            }

            Section {
                if viewModel.isPayoutKind {
                    HStack(spacing: ExperienceSpacing.xs) {
                        Text("$")
                            .experienceStyle(.body, color: colors.secondaryText)
                        TextField("0.00", text: $viewModel.payoutAmountText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .payout)
                            .accessibilityIdentifier("createAchievement.payout")
                    }
                    .tradeTraxsFormRowBackground(active: usesTradeTraxsFormSurfaces, layer: .input, colors: colors)
                }

                DatePicker(
                    "Date Achieved",
                    selection: $viewModel.achievedAt,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .tradeTraxsFormRowBackground(active: usesTradeTraxsFormSurfaces, layer: .input, colors: colors)
            } header: {
                sectionHeader("Achievement Value")
            }

            Section {
                if let preview = viewModel.imagePreview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                        .accessibilityLabel("Achievement image preview")
                        .tradeTraxsFormRowBackground(active: usesTradeTraxsFormSurfaces, layer: .input, colors: colors)

                    HStack(spacing: ExperienceSpacing.md) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text("Replace")
                                .font(ExperienceTypography.subheadline.weight(.semibold))
                                .foregroundStyle(colors.accent)
                        }
                        .accessibilityIdentifier("createAchievement.media.picker")

                        Button("Remove", role: .destructive) {
                            viewModel.clearImage()
                            photoItem = nil
                        }
                        .font(ExperienceTypography.subheadline.weight(.semibold))
                    }
                    .tradeTraxsFormRowBackground(active: usesTradeTraxsFormSurfaces, layer: .surface, colors: colors)
                } else {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        CreateComposerAttachmentAction(
                            systemImage: "photo.badge.plus",
                            title: "Add Photo"
                        )
                    }
                    .accessibilityIdentifier("createAchievement.media.picker")
                    .tradeTraxsFormRowBackground(active: usesTradeTraxsFormSurfaces, layer: .input, colors: colors)
                }
            } header: {
                sectionHeader("Media")
            } footer: {
                if viewModel.imagePreview == nil {
                    sectionFooter("Screenshot or proof image required.")
                }
            }

            Section {
                SettingsToggleRow(
                    title: "Public",
                    subtitle: "Show on your profile and feed when published.",
                    isOn: $viewModel.isPublic
                )
                .tradeTraxsFormRowBackground(active: usesTradeTraxsFormSurfaces, layer: .input, colors: colors)
            } header: {
                sectionHeader("Visibility")
            }

            if let formError = viewModel.formError {
                Section {
                    Text(formError)
                        .foregroundStyle(colors.loss)
                        .font(.footnote)
                        .accessibilityIdentifier("createAchievement.formError")
                        .tradeTraxsFormRowBackground(active: usesTradeTraxsFormSurfaces, layer: .surface, colors: colors)
                }
            }

            Section {
                ExperienceButton(
                    title: submitButtonTitle,
                    kind: .primary,
                    isEnabled: viewModel.canPublish,
                    isLoading: viewModel.phase == .publishing,
                    accessibilityIdentifier: "createAchievement.publish"
                ) {
                    viewModel.publish()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
                .listRowBackground(Color.clear)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(ExperienceSpacing.sm)
        .disabled(viewModel.phase == .publishing)
        .experienceKeyboardDoneToolbar()
        .onAppear { viewModel.loadAccountsIfNeeded() }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        if usesTradeTraxsFormSurfaces {
            Text(title.uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.secondaryText)
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    private func sectionFooter(_ text: String) -> some View {
        if usesTradeTraxsFormSurfaces {
            Text(text)
                .foregroundStyle(colors.tertiaryText)
        } else {
            Text(text)
        }
    }

    private var submitButtonTitle: String {
        if viewModel.phase == .publishing {
            return viewModel.isUploadingMedia ? "Uploading…" : "Creating…"
        }
        return "Create Achievement"
    }

    @ViewBuilder
    private var accountField: some View {
        if viewModel.isLoadingAccounts && viewModel.accounts.isEmpty {
            HStack(spacing: ExperienceSpacing.sm) {
                ProgressView()
                Text("Loading accounts…")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        } else {
            Picker("Trading Account", selection: Binding(
                get: { viewModel.selectedAccountID?.rawValue ?? "" },
                set: { raw in
                    viewModel.selectAccount(raw.isEmpty ? nil : TradingAccountID(raw))
                }
            )) {
                Text("None").tag("")
                ForEach(viewModel.accountsForPicker) { account in
                    OwnerAccountDropdownPickerLabel(account: account)
                        .tag(account.id.rawValue)
                }
            }
            .accessibilityIdentifier("createAchievement.account")
            .onAppear {
                OwnerAccountDropdownSupport.logBoundary(
                    .achievement,
                    accounts: viewModel.accountsForPicker,
                    profileID: viewModel.ownerAccountsProfileID
                )
            }
        }
    }

    private var kindField: some View {
        Picker("Type", selection: Binding(
            get: { viewModel.kind },
            set: { viewModel.selectKind($0) }
        )) {
            ForEach(CreateAchievementViewModel.allKinds, id: \.self) { kind in
                Text(CreateAchievementViewModel.displayTitle(for: kind))
                    .tag(kind)
            }
        }
        .accessibilityIdentifier("createAchievement.kindPicker")
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

private extension View {
    @ViewBuilder
    func tradeTraxsFormRowBackground(
        active: Bool,
        layer: TradeTraxsFormSurfaceLayer,
        colors: SemanticColorPalette
    ) -> some View {
        if active {
            listRowBackground(layer.color(from: colors))
        } else {
            self
        }
    }
}
