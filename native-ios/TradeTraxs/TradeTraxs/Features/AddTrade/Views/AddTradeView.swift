import AVKit
import PhotosUI
import SwiftUI
import UIKit

/// Native Add Trade — compact trading-first layout; progressive disclosure for review/media.
struct AddTradeView: View {
    @State private var viewModel: AddTradeViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var clipVideoItem: PhotosPickerItem?
    @State private var showsDiscardConfirm = false
    @State private var showsReview = false
    @State private var showsNotes = false
    @State private var showsClipMenu = false
    @State private var showsNewClipComposer = false
    @State private var showsReelPicker = false
    @State private var showsClipCamera = false
    @State private var showsClipPreview = false
    @State private var showsInstrumentPicker = false
    @State private var didApplyScreenshotPrefill = false
    @FocusState private var focusedField: AddTradeViewModel.Field?

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        mode: AddTradeViewModel.Mode = .create,
        onDismiss: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: AddTradeViewModel(
                trades: data.trades,
                feed: data.feed,
                session: data.session,
                detailCache: data.detailCache,
                uploadService: data.uploadService,
                objectStorage: data.objectStorage,
                imagePipeline: data.imagePipeline,
                mode: mode,
                onDismiss: onDismiss
            )
        )
    }

    init(viewModel: AddTradeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loadingAccounts:
                ProgressView("Loading accounts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ExperienceErrorState(
                    title: viewModel.loadFailureTitle,
                    message: message,
                    onRetry: { viewModel.retryLoad() }
                )
            case .ready, .saving:
                formContent
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle(viewModel.navigationTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { requestDismiss() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.phase == .ready || viewModel.phase == .saving {
                saveBar
            }
        }
        .sheet(isPresented: $showsInstrumentPicker) {
            NavigationStack {
                AddTradeInstrumentPickerView(
                    recentSymbols: viewModel.recentSymbols,
                    selectedSymbol: viewModel.symbolText,
                    startInCustomEntry: ProcessInfo.processInfo.arguments.contains("-uitesting-addtrade-custom"),
                    initialCustomText: ProcessInfo.processInfo.arguments.contains("-uitesting-addtrade-custom")
                        ? "MGC"
                        : "",
                    onSelect: { ticker in
                        viewModel.applySymbol(ticker)
                        showsInstrumentPicker = false
                    },
                    onCustom: { ticker in
                        viewModel.applyCustomSymbol(ticker)
                        showsInstrumentPicker = false
                    },
                    onClose: { showsInstrumentPicker = false }
                )
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsReview) {
            NavigationStack {
                AddTradeReviewView(viewModel: viewModel)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsNotes) {
            NavigationStack {
                AddTradeNotesView(viewModel: viewModel)
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Add Clip",
            isPresented: $showsClipMenu,
            titleVisibility: .visible
        ) {
            Button("Create New Clip") { showsNewClipComposer = true }
            Button("Link Existing Clip") {
                showsReelPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showsNewClipComposer) {
            NavigationStack {
                AddTradeNewClipComposerView(
                    isPreparing: viewModel.isPreparingClipVideo,
                    draft: viewModel.reelDraft,
                    contextNote: viewModel.clipContextNote,
                    videoItem: $clipVideoItem,
                    onRecord: {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            showsClipCamera = true
                        }
                    },
                    onClear: {
                        viewModel.clearReelDraft()
                        clipVideoItem = nil
                    },
                    onPreview: { showsClipPreview = true },
                    onDone: { showsNewClipComposer = false }
                )
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsReelPicker) {
            NavigationStack {
                ReelPickerView(
                    reels: viewModel.unattachedReels,
                    isLoading: viewModel.isLoadingReels,
                    onSelect: { reel in
                        viewModel.selectLinkedReel(reel)
                        showsReelPicker = false
                    },
                    onClose: { showsReelPicker = false }
                )
            }
            .presentationDetents([.medium, .large])
            .onAppear { viewModel.loadUnattachedReelsIfNeeded() }
        }
        .fullScreenCover(isPresented: $showsClipCamera) {
            CameraVideoPicker(
                onPicked: { url in
                    showsClipCamera = false
                    viewModel.applyClipVideo(from: url, contentType: "video/quicktime")
                },
                onCancel: { showsClipCamera = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsClipPreview) {
            if let url = viewModel.reelDraft?.localVideoURL {
                NavigationStack {
                    VideoPlayer(player: AVPlayer(url: url))
                        .experienceSwipeToDismiss { showsClipPreview = false }
                        .experienceNavigationTitle("Clip Preview")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showsClipPreview = false }
                            }
                        }
                }
            }
        }
        .confirmationDialog(
            "Discard this trade?",
            isPresented: $showsDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { viewModel.dismissRequested() }
            Button("Keep Editing", role: .cancel) {}
        }
        .experienceSwipeToDismiss { requestDismiss() }
        .interactiveDismissDisabled()
        .task { viewModel.loadIfNeeded() }
        .onChange(of: AccountMutationStore.shared.revision) { _, _ in
            viewModel.reloadAccountsAfterMutation()
        }
        .onChange(of: viewModel.phase) { _, phase in
            #if DEBUG
            if phase == .ready || phase == .saving {
                applyScreenshotPrefillIfNeeded()
            }
            #endif
        }
        .onChange(of: photoItem) { _, item in
            Task { await loadPhoto(item) }
        }
        .onChange(of: clipVideoItem) { _, item in
            Task { await loadClipVideo(item) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .accessibilityIdentifier("addTrade.root")
    }

    private var formContent: some View {
        Form {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitesting-addtrade-media") {
                screenshotSection
            }
            if ProcessInfo.processInfo.arguments.contains("-uitesting-addtrade-reel-draft"),
               viewModel.reelDraft != nil
            {
                clipDraftScreenshotSection
            }
            #endif

            Section {
                accountPicker
                instrumentRow
                Picker("Direction", selection: $viewModel.side) {
                    Text("Long").tag(TradeSide.long)
                    Text("Short").tag(TradeSide.short)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .accessibilityLabel("Trade direction")
            } header: {
                Text("Trade")
            } footer: {
                if viewModel.eligibleAccounts.isEmpty {
                    Text("No accounts can accept new trades. Free plan allows up to \(FreeTierPolicy.maxTradeEntryAccounts) entry-enabled accounts.")
                }
            }

            Section("Risk & Result") {
                HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("P&L")
                            .experienceStyle(.caption, color: colors.secondaryText)
                        TextField("+$660.00", text: $viewModel.pnlText)
                            .keyboardType(.numbersAndPunctuation)
                            .focused($focusedField, equals: .pnl)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(pnlFieldColor)
                            .accessibilityLabel("Profit and loss")
                            .accessibilityIdentifier("addTrade.pnl")
                        if let error = viewModel.fieldErrors[.pnl] {
                            Text(error).foregroundStyle(colors.loss).font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Risk / Reward")
                            .experienceStyle(.caption, color: colors.secondaryText)
                        HStack(spacing: ExperienceSpacing.xs) {
                            Text("1 :")
                                .experienceStyle(.body, color: colors.secondaryText)
                            TextField("2.35", text: $viewModel.rrText)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .rr)
                                .accessibilityLabel("Risk reward ratio")
                                .accessibilityIdentifier("addTrade.rr")
                        }
                        if let error = viewModel.fieldErrors[.rr] {
                            Text(error).foregroundStyle(colors.loss).font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            Section("Execution") {
                HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                    compactNumericField(
                        "Entry Price",
                        text: $viewModel.entryPriceText,
                        field: .entry,
                        error: viewModel.fieldErrors[.entry]
                    )
                    compactNumericField(
                        "Exit Price",
                        text: $viewModel.exitPriceText,
                        field: .exit,
                        error: viewModel.fieldErrors[.exit]
                    )
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                    compactNumericField(
                        "Contracts",
                        text: $viewModel.contractsText,
                        field: .contracts,
                        error: viewModel.fieldErrors[.contracts]
                    )
                    compactNumericField(
                        "Points",
                        text: $viewModel.pointsText,
                        field: .points,
                        error: viewModel.fieldErrors[.points]
                    )
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            Section("Timing") {
                DatePicker("Entry", selection: $viewModel.entryAt)
                Toggle("Include exit time", isOn: $viewModel.includeExitTime)
                if viewModel.includeExitTime {
                    DatePicker("Exit", selection: $viewModel.exitAt)
                }
            }

            Section("Trade Review") {
                Button {
                    showsReview = true
                } label: {
                    SettingsNavigationRow(
                        title: "Strategy & details",
                        subtitle: viewModel.reviewSummary,
                        systemImage: "list.bullet.rectangle"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showsNotes = true
                } label: {
                    SettingsNavigationRow(
                        title: "Notes",
                        subtitle: viewModel.notesText.isEmpty ? "Add notes" : viewModel.notesText,
                        systemImage: "note.text"
                    )
                }
                .buttonStyle(.plain)
            }

            #if DEBUG
            if !ProcessInfo.processInfo.arguments.contains("-uitesting-addtrade-media") {
                mediaContentSection
            }
            #else
            mediaContentSection
            #endif

            Section("Sharing") {
                Toggle("Share to Profile", isOn: $viewModel.shareToProfile)
                if viewModel.shareToProfile {
                    TextField("Caption (optional)", text: $viewModel.publicCaptionText)
                }
            }

            if let formError = viewModel.formError {
                Section {
                    Text(formError)
                        .foregroundStyle(colors.loss)
                        .font(.footnote)
                        .accessibilityIdentifier("addTrade.formError")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .disabled(viewModel.phase == .saving)
        .listSectionSpacing(ExperienceSpacing.sm)
    }

    private var pnlFieldColor: Color {
        let trimmed = viewModel.pnlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let value = Decimal(string: trimmed.replacingOccurrences(of: ",", with: ""))
        else { return colors.primaryText }
        if value > 0 { return colors.profit }
        if value < 0 { return colors.loss }
        return colors.primaryText
    }

    private var instrumentRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                showsInstrumentPicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Instrument")
                            .experienceStyle(.caption, color: colors.secondaryText)
                        Text(viewModel.symbolText.isEmpty ? "Select or custom" : viewModel.symbolText)
                            .experienceStyle(
                                .body,
                                color: viewModel.symbolText.isEmpty ? colors.tertiaryText : colors.primaryText
                            )
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addTrade.instrument")
            .accessibilityLabel(
                viewModel.symbolText.isEmpty
                    ? "Instrument, not selected"
                    : "Instrument \(viewModel.symbolText)"
            )
            if let error = viewModel.fieldErrors[.symbol] {
                Text(error)
                    .foregroundStyle(colors.loss)
                    .font(.caption)
            }
        }
    }

    private var mediaContentSection: some View {
        Section("Media & Content") {
            if let preview = viewModel.screenshotPreview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                    .accessibilityLabel("Trade screenshot preview")
                Button("Remove Screenshot", role: .destructive) {
                    viewModel.clearScreenshot()
                    photoItem = nil
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(
                    viewModel.screenshotPreview == nil ? "Add Screenshot" : "Replace Screenshot",
                    systemImage: "photo.on.rectangle"
                )
            }
            .accessibilityIdentifier("addTrade.media.picker")

            if let draft = viewModel.reelDraft {
                HStack(spacing: ExperienceSpacing.sm) {
                    if let thumb = draft.thumbnailPreview {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 64)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundStyle(colors.accent)
                            .frame(width: 44, height: 64)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New clip draft")
                            .experienceStyle(.body, color: colors.primaryText)
                        Text(draft.formattedDuration)
                            .experienceStyle(.caption, color: colors.secondaryText)
                        Text(viewModel.clipContextNote)
                            .experienceStyle(.caption, color: colors.tertiaryText)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        viewModel.clearClip()
                        clipVideoItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(colors.secondaryText)
                    }
                    .accessibilityLabel("Remove clip draft")
                }
                .accessibilityIdentifier("addTrade.reelDraft")
            } else if let reel = viewModel.linkedReel {
                HStack(spacing: ExperienceSpacing.sm) {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundStyle(colors.accent)
                        .frame(width: 36, height: 48)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reel.caption ?? "Existing clip")
                            .experienceStyle(.body, color: colors.primaryText)
                            .lineLimit(2)
                        if let seconds = reel.durationSeconds {
                            Text(MediaVideoPreparation.formatDuration(seconds))
                                .experienceStyle(.caption, color: colors.secondaryText)
                        }
                    }
                    Spacer()
                    Button {
                        viewModel.clearClip()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(colors.secondaryText)
                    }
                    .accessibilityLabel("Remove linked clip")
                }
                .accessibilityIdentifier("addTrade.linkedReel")
            }

            Button {
                showsClipMenu = true
            } label: {
                Label(
                    (viewModel.reelDraft == nil && viewModel.linkedReel == nil)
                        ? "Add Clip"
                        : "Change Clip",
                    systemImage: "play.rectangle"
                )
            }
            .accessibilityIdentifier("addTrade.addClip")
        }
    }

    #if DEBUG
    private var clipDraftScreenshotSection: some View {
        Section("Clip") {
            if let draft = viewModel.reelDraft {
                HStack(spacing: ExperienceSpacing.sm) {
                    if let thumb = draft.thumbnailPreview {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 64)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New clip draft")
                            .experienceStyle(.body, color: colors.primaryText)
                        Text(draft.formattedDuration)
                            .experienceStyle(.caption, color: colors.secondaryText)
                        Text(viewModel.clipContextNote)
                            .experienceStyle(.caption, color: colors.tertiaryText)
                            .lineLimit(2)
                    }
                }
                .accessibilityIdentifier("addTrade.reelDraft")
            }
        }
    }
    #endif

    private var screenshotSection: some View {
        // DEBUG media screenshot launch arg — keep screenshot block near top.
        Section("Screenshot") {
            if let preview = viewModel.screenshotPreview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                Button("Remove Screenshot", role: .destructive) {
                    viewModel.clearScreenshot()
                    photoItem = nil
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(
                    viewModel.screenshotPreview == nil ? "Add Screenshot" : "Replace Screenshot",
                    systemImage: "photo.on.rectangle"
                )
            }
        }
    }

    private var accountPicker: some View {
        Picker("Account", selection: Binding(
            get: { viewModel.selectedAccountID?.rawValue ?? "" },
            set: { viewModel.selectAccount(TradingAccountID($0)) }
        )) {
            ForEach(viewModel.accountsForPicker) { account in
                Text(accountLabel(account)).tag(account.id.rawValue)
            }
        }
        .accessibilityIdentifier("addTrade.account")
    }

    private func accountLabel(_ account: TradingAccount) -> String {
        TradingAccountDisplay.title(for: account, audience: .owner)
    }

    private func compactNumericField(
        _ title: String,
        text: Binding<String>,
        field: AddTradeViewModel.Field,
        error: String?,
        keyboard: UIKeyboardType = .decimalPad
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .experienceStyle(.caption, color: colors.secondaryText)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .focused($focusedField, equals: field)
            if let error {
                Text(error).foregroundStyle(colors.loss).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    #if DEBUG
    private func applyScreenshotPrefillIfNeeded() {
        guard !didApplyScreenshotPrefill else { return }
        let args = ProcessInfo.processInfo.arguments
        let wantsAny = args.contains("-uitesting-addtrade-home")
            || args.contains("-uitesting-addtrade-filled")
            || args.contains("-uitesting-addtrade-review")
            || args.contains("-uitesting-addtrade-media")
            || args.contains("-uitesting-addtrade-validation")
            || args.contains("-uitesting-addtrade-reel")
            || args.contains("-uitesting-addtrade-reel-draft")
            || args.contains("-uitesting-addtrade-reel-picker")
            || args.contains("-uitesting-addtrade-reel-selected")
            || args.contains("-uitesting-addtrade-custom")
            || args.contains("-uitesting-addtrade-compact")
        guard wantsAny else { return }
        didApplyScreenshotPrefill = true

        if args.contains("-uitesting-addtrade-home") {
            viewModel.applySymbol("MNQ")
            viewModel.side = .long
        }
        if args.contains("-uitesting-addtrade-filled")
            || args.contains("-uitesting-addtrade-review")
            || args.contains("-uitesting-addtrade-media")
            || args.contains("-uitesting-addtrade-reel")
            || args.contains("-uitesting-addtrade-reel-draft")
            || args.contains("-uitesting-addtrade-reel-picker")
            || args.contains("-uitesting-addtrade-reel-selected")
            || args.contains("-uitesting-addtrade-compact")
        {
            viewModel.applyScreenshotFixture()
        }
        if args.contains("-uitesting-addtrade-custom") {
            // Keep form behind picker light; custom entry UI is the focus.
            viewModel.side = .long
        }
        if args.contains("-uitesting-addtrade-media") {
            viewModel.applyScreenshotMediaFixture()
        }
        if args.contains("-uitesting-addtrade-validation") {
            viewModel.symbolText = ""
            viewModel.pnlText = "not-a-number"
            viewModel.save()
        }
        if args.contains("-uitesting-addtrade-review") {
            showsReview = true
        }
        if args.contains("-uitesting-addtrade-custom") {
            showsInstrumentPicker = true
        }
        if args.contains("-uitesting-addtrade-reel-draft")
            || args.contains("-uitesting-addtrade-reel")
        {
            viewModel.applyClipDraftFixture()
            if args.contains("-uitesting-addtrade-reel") {
                showsNewClipComposer = true
            }
        }
        if args.contains("-uitesting-addtrade-reel-picker")
            || args.contains("-uitesting-addtrade-reel-selected")
        {
            viewModel.loadUnattachedReelsIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if args.contains("-uitesting-addtrade-reel-selected"),
                   let reel = viewModel.unattachedReels.first
                {
                    viewModel.selectLinkedReel(reel)
                }
                if args.contains("-uitesting-addtrade-reel-picker") {
                    showsReelPicker = true
                }
            }
        }
    }
    #endif

    private func loadClipVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let movie = try await item.loadTransferable(type: MovieFileTransferable.self) {
                viewModel.applyClipVideo(from: movie.url, contentType: "video/quicktime")
            } else {
                viewModel.formError = "Couldn't read that video. Try MP4 or MOV."
            }
        } catch {
            viewModel.formError = "Couldn't read that video. Try MP4 or MOV."
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            ExperienceButton(
                title: viewModel.phase == .saving
                    ? (viewModel.isUploadingMedia ? "Uploading…" : "Saving…")
                    : viewModel.primarySaveTitle,
                kind: .primary,
                isEnabled: viewModel.canSave && viewModel.phase != .saving,
                isLoading: viewModel.phase == .saving,
                accessibilityIdentifier: "addTrade.save"
            ) {
                focusedField = nil
                viewModel.save()
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
            viewModel.setScreenshot(image)
        }
    }
}

// MARK: - Instrument picker

struct AddTradeInstrumentPickerView: View {
    let recentSymbols: [String]
    let selectedSymbol: String
    var startInCustomEntry: Bool = false
    var initialCustomText: String = ""
    var onSelect: (String) -> Void
    var onCustom: (String) -> Void
    var onClose: () -> Void

    @State private var searchText = ""
    @State private var customText = ""
    @State private var showsCustomEntry = false
    @Environment(\.themeColors) private var colors

    private var filtered: [String] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !q.isEmpty else { return recentSymbols }
        return recentSymbols.filter { $0.contains(q) }
    }

    @ViewBuilder
    private var customInstrumentSection: some View {
        Section {
            if showsCustomEntry {
                TextField("Symbol", text: $customText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("addTrade.instrument.customField")
                Button("Use \(AddTradeViewModel.normalizeSymbol(customText).isEmpty ? "Symbol" : AddTradeViewModel.normalizeSymbol(customText))") {
                    onCustom(customText)
                }
                .disabled(AddTradeViewModel.normalizeSymbol(customText).isEmpty)
                .accessibilityIdentifier("addTrade.instrument.customConfirm")
            } else {
                Button {
                    showsCustomEntry = true
                    customText = searchText
                } label: {
                    Label("Custom Instrument", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("addTrade.instrument.custom")
            }
        } header: {
            Text(showsCustomEntry ? "Custom Instrument" : "")
        } footer: {
            Text("Custom symbols are stored as the trade ticker — same as web free-text entry.")
        }
    }

    @ViewBuilder
    private var recentInstrumentsSection: some View {
        if !filtered.isEmpty {
            Section("Recent") {
                ForEach(filtered, id: \.self) { ticker in
                    Button {
                        onSelect(ticker)
                    } label: {
                        HStack {
                            Text(ticker)
                                .experienceStyle(.body, color: colors.primaryText)
                            Spacer()
                            if ticker == selectedSymbol.uppercased() {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(colors.accent)
                            }
                        }
                    }
                    .accessibilityIdentifier("addTrade.instrument.\(ticker)")
                }
            }
        } else if !searchText.isEmpty {
            Section {
                Text("No recent match — use Custom Instrument.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
    }

    var body: some View {
        List {
            // When entering a custom symbol, keep that field above Recent so it stays visible.
            if showsCustomEntry {
                customInstrumentSection
                recentInstrumentsSection
            } else {
                recentInstrumentsSection
                customInstrumentSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .searchable(text: $searchText, prompt: "Search your instruments")
        .experienceNavigationTitle("Instrument")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
        }
        .accessibilityIdentifier("addTrade.instrumentPicker")
        .onAppear {
            if startInCustomEntry {
                showsCustomEntry = true
                if !initialCustomText.isEmpty {
                    customText = initialCustomText
                }
            }
        }
    }
}

struct AddTradeReviewView: View {
    @Bindable var viewModel: AddTradeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Strategy") {
                TextField("Strategy / setup", text: $viewModel.strategyText)
            }
        }
        .experienceNavigationTitle("Trade Review")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .accessibilityIdentifier("addTrade.review")
    }
}

struct AddTradeNotesView: View {
    @Bindable var viewModel: AddTradeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextEditor(text: $viewModel.notesText)
                    .frame(minHeight: 180)
                    .accessibilityLabel("Trade notes")
            } footer: {
                Text("Private journal notes (Top Confluences on web).")
            }
        }
        .experienceNavigationTitle("Notes")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .accessibilityIdentifier("addTrade.notes")
    }
}

/// Compact create-new-clip sheet used from Add Trade (local draft only).
struct AddTradeNewClipComposerView: View {
    var isPreparing: Bool
    var draft: ReelDraft?
    var contextNote: String
    @Binding var videoItem: PhotosPickerItem?
    var onRecord: () -> Void
    var onClear: () -> Void
    var onPreview: () -> Void
    var onDone: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Form {
            Section {
                if isPreparing {
                    ProgressView("Preparing video…")
                } else if let draft, let thumb = draft.thumbnailPreview {
                    Button(action: onPreview) {
                        HStack(spacing: ExperienceSpacing.sm) {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 84)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Clip ready")
                                    .experienceStyle(.headline, color: colors.primaryText)
                                Text(draft.formattedDuration)
                                    .experienceStyle(.caption, color: colors.secondaryText)
                                Text("Tap to preview")
                                    .experienceStyle(.caption, color: colors.accent)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addTrade.newClip.preview")

                    PhotosPicker(selection: $videoItem, matching: .videos) {
                        Label("Replace Video", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button("Remove Video", role: .destructive, action: onClear)
                } else {
                    PhotosPicker(selection: $videoItem, matching: .videos) {
                        Label("Choose Video", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("addTrade.newClip.choose")
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Record Video", action: onRecord)
                            .accessibilityIdentifier("addTrade.newClip.record")
                    }
                }
            } footer: {
                Text("MP4/MOV · max 90s · 100 MB. Uploads when you Save Trade.")
            }

            Section {
                Text(contextNote)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } header: {
                Text("Linked to this trade")
            }
        }
        .experienceNavigationTitle("New Clip")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
                    .disabled(draft == nil && !isPreparing)
            }
        }
        .accessibilityIdentifier("addTrade.newClip")
    }
}
