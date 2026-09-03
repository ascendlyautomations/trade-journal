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
                composerContent
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("New Achievement")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { requestDismiss() }
                    .font(.body.weight(.regular))
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

    private var composerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                introHeader
                kindSelectionGrid
                detailsSection

                if viewModel.isPayoutKind {
                    payoutSection
                }

                accountSection
                imageSection

                if let formError = viewModel.formError {
                    Text(formError)
                        .experienceStyle(.footnote, color: colors.loss)
                        .accessibilityIdentifier("createAchievement.formError")
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.sm)
            .padding(.bottom, ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(viewModel.phase == .publishing)
        .experienceKeyboardDoneToolbar()
        .onAppear { viewModel.loadAccountsIfNeeded() }
    }

    private var introHeader: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            ZStack {
                Circle()
                    .fill(colors.accentMuted)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colors.accent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text("Share a milestone")
                    .experienceStyle(.headline, color: colors.primaryText)
                Text("Celebrate payouts, evaluations, and trading wins with your profile.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
    }

    private var kindSelectionGrid: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            CreateComposerSectionLabel(title: "Achievement type")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: ExperienceSpacing.sm),
                    GridItem(.flexible(), spacing: ExperienceSpacing.sm),
                ],
                spacing: ExperienceSpacing.sm
            ) {
                ForEach(CreateAchievementViewModel.allKinds, id: \.self) { kind in
                    kindCard(for: kind)
                }
            }
            .accessibilityIdentifier("createAchievement.kindPicker")
        }
    }

    private func kindCard(for kind: AchievementKind) -> some View {
        let isSelected = viewModel.kind == kind
        return Button {
            viewModel.selectKind(kind)
        } label: {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Image(systemName: Self.icon(for: kind))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? colors.accent : colors.secondaryText)
                Text(CreateAchievementViewModel.displayTitle(for: kind))
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(ExperienceSpacing.sm)
            .background(
                isSelected ? colors.accentMuted : colors.surfaceSecondary,
                in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                    .strokeBorder(
                        isSelected ? colors.accent : colors.border.opacity(ExperienceOpacity.subtle),
                        lineWidth: isSelected ? 1.5 : ExperienceBorder.hairline
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            CreateComposerSectionLabel(title: "Details")

            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text("Title")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                    TextField("What did you achieve?", text: $viewModel.titleText)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.next)
                        .accessibilityIdentifier("createAchievement.title")
                }

                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text("Description")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                    CreateComposerMultilineField(
                        text: $viewModel.descriptionText,
                        placeholder: "Optional context for your achievement…",
                        minHeight: 64,
                        accessibilityLabel: "Achievement description"
                    )
                }

                DatePicker("Achieved", selection: $viewModel.achievedAt, displayedComponents: [.date, .hourAndMinute])

                Toggle("Public", isOn: $viewModel.isPublic)
            }
            .padding(ExperienceSpacing.sm)
            .background(
                colors.surfaceSecondary,
                in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
            )
        }
    }

    private var payoutSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            CreateComposerSectionLabel(title: "Payout")

            HStack(spacing: ExperienceSpacing.xs) {
                Text("$")
                    .experienceStyle(.title3, color: colors.secondaryText)
                TextField("Amount", text: $viewModel.payoutAmountText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("createAchievement.payout")
            }
            .padding(ExperienceSpacing.sm)
            .background(
                colors.surfaceSecondary,
                in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
            )
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            CreateComposerSectionLabel(title: "Trading account")

            Group {
                if viewModel.isLoadingAccounts && viewModel.accounts.isEmpty {
                    HStack(spacing: ExperienceSpacing.sm) {
                        ProgressView()
                        Text("Loading accounts…")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                    }
                } else {
                    Picker("Account", selection: Binding(
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
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.vertical, ExperienceSpacing.xs)
            .background(
                colors.surfaceSecondary,
                in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
            )

            Text("Optional — link an account when it applies.")
                .experienceStyle(.caption, color: colors.tertiaryText)
        }
    }

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            CreateComposerSectionLabel(title: "Image")

            if let preview = viewModel.imagePreview {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 220)
                        .clipped()
                        .clipShape(
                            RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                                .stroke(
                                    colors.border.opacity(ExperienceOpacity.subtle),
                                    lineWidth: ExperienceBorder.hairline
                                )
                        }
                        .accessibilityLabel("Achievement image preview")

                    CreateComposerPreviewDismissButton(accessibilityLabel: "Remove image") {
                        viewModel.clearImage()
                        photoItem = nil
                    }
                    .padding(ExperienceSpacing.sm)
                }

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text("Change")
                        .font(ExperienceTypography.subheadline.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }
                .accessibilityIdentifier("createAchievement.media.picker")
            } else {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    CreateComposerAttachmentAction(
                        systemImage: "photo",
                        title: "Add image"
                    )
                }
                .accessibilityIdentifier("createAchievement.media.picker")

                Text("Required — use a screenshot or proof image.")
                    .experienceStyle(.caption, color: colors.tertiaryText)
                    .padding(.leading, 2)
            }
        }
    }

    private var publishBar: some View {
        CreateComposerPublishBar(
            title: "Publish",
            loadingTitle: viewModel.isUploadingMedia ? "Uploading…" : "Publishing…",
            isEnabled: viewModel.canPublish,
            isLoading: viewModel.phase == .publishing,
            accessibilityIdentifier: "createAchievement.publish"
        ) {
            viewModel.publish()
        }
    }

    private static func icon(for kind: AchievementKind) -> String {
        switch kind {
        case .propFirmPayout: return "dollarsign.circle.fill"
        case .liveTradingPayout: return "banknote.fill"
        case .passedEvaluation: return "checkmark.seal.fill"
        case .milestone: return "flag.checkered"
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
