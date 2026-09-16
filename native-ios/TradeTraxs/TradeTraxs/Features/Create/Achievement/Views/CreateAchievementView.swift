import PhotosUI
import SwiftUI
import UIKit

/// Native Create Achievement — mirrors web `AchievementUploadModal` required fields.
struct CreateAchievementView: View {
    @State private var viewModel: CreateAchievementViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var showsDiscardConfirm = false
    @State private var didApplyScreenshotPrefill = false
    @State private var cropSourceImage: UIImage?

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
        prefill: CreateAchievementPrefill? = nil,
        onDismiss: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: CreateAchievementViewModel(
                achievements: data.achievements,
                trades: data.trades,
                session: data.session,
                uploadServices: data.globalUploadServices(),
                prefill: prefill,
                onDismiss: onDismiss
            )
        )
    }

    init(
        data: DataEnvironment,
        onDismiss: @escaping () -> Void
    ) {
        self.init(data: data, prefill: nil, onDismiss: onDismiss)
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
                ExperienceArrowBackButton(action: requestDismiss)
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
        .experienceProtectedFormDismiss()
        .task { viewModel.loadIfNeeded() }
        .onChange(of: viewModel.phase) { _, phase in
            #if DEBUG
            if phase == .ready { applyScreenshotPrefillIfNeeded() }
            #endif
        }
        .onChange(of: photoItem) { _, item in
            Task { await presentCrop(for: item) }
        }
        .imageCropSelection(
            sourceImage: $cropSourceImage,
            preset: .socialContent,
            onConfirm: { result in
                viewModel.setImage(result)
                cropSourceImage = nil
                photoItem = nil
            },
            onCancel: { photoItem = nil }
        )
        .accessibilityIdentifier("createAchievement.root")
    }

    private var composerContent: some View {
        Form {
            Section("Achievement Details") {
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
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.sentences)
                    .tradeTraxsFormRowBackground(active: usesTradeTraxsFormSurfaces, layer: .input, colors: colors)
            }

            Section("Achievement Value") {
                if viewModel.isPayoutKind {
                    HStack(spacing: ExperienceSpacing.xxs) {
                        Text("$")
                            .experienceStyle(.body, color: colors.secondaryText)
                        TextField("0.00", text: $viewModel.payoutAmountText.numericInput(.unsignedCurrency))
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
            }

            Section {
                if let preview = viewModel.finalImage {
                    AdaptiveMediaPreviewImage(image: preview)
                        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                        .accessibilityLabel("Achievement image preview")
                        .tradeTraxsFormRowBackground(active: usesTradeTraxsFormSurfaces, layer: .input, colors: colors)

                    HStack(spacing: ExperienceSpacing.sm) {
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

                Toggle("Share to Profile", isOn: $viewModel.isPublic)
                    .accessibilityIdentifier("createAchievement.shareToProfile")
                    .listRowInsets(
                        EdgeInsets(
                            top: ExperienceSpacing.xxs,
                            leading: ExperienceSpacing.md,
                            bottom: ExperienceSpacing.xxs,
                            trailing: ExperienceSpacing.md
                        )
                    )
                    .tradeTraxsFormRowBackground(active: usesTradeTraxsFormSurfaces, layer: .input, colors: colors)
            } header: {
                Text("Media")
            } footer: {
                if viewModel.finalImage == nil {
                    Text("Screenshot or proof image required.")
                        .foregroundStyle(colors.tertiaryText)
                }
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
                .listRowInsets(
                    EdgeInsets(
                        top: ExperienceSpacing.xxs,
                        leading: 0,
                        bottom: ExperienceSpacing.xs,
                        trailing: 0
                    )
                )
                .listRowBackground(Color.clear)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(ExperienceSpacing.xs)
        .disabled(viewModel.phase == .publishing)
        .experienceFormKeyboard(focus: $focusedField)
        .onAppear { viewModel.loadAccountsIfNeeded() }
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

    @ViewBuilder
    private var kindField: some View {
        if viewModel.lockKind {
            LabeledContent("Type", value: CreateAchievementViewModel.displayTitle(for: viewModel.kind))
                .accessibilityIdentifier("createAchievement.kindLocked")
        } else {
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
    }

    private func requestDismiss() {
        if viewModel.hasUnsavedChanges {
            showsDiscardConfirm = true
        } else {
            viewModel.dismissRequested()
        }
    }

    private func presentCrop(for item: PhotosPickerItem?) async {
        guard let image = await ImageCropSelectionSupport.loadUIImage(from: item) else { return }
        cropSourceImage = image
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

