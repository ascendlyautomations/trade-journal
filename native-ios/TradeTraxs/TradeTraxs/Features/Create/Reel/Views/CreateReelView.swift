import AVKit
import PhotosUI
import SwiftUI
import UIKit

/// Standalone New Clip / Reel composer — video first, then caption + optional trade link.
struct CreateReelView: View {
    @State private var viewModel: CreateReelViewModel
    @State private var videoItem: PhotosPickerItem?
    @State private var showsDiscardConfirm = false
    @State private var showsTradePicker = false
    @State private var showsCamera = false
    @State private var showsPreview = false
    @State private var didApplyScreenshotPrefill = false

    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        onDismiss: @escaping () -> Void
    ) {
        imagePipeline = data.imagePipeline
        _viewModel = State(
            initialValue: CreateReelViewModel(
                feed: data.feed,
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                uploadService: data.uploadService,
                objectStorage: data.objectStorage,
                onDismiss: onDismiss
            )
        )
    }

    init(viewModel: CreateReelViewModel) {
        imagePipeline = PlaceholderImagePipeline()
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
                    title: "Couldn't open New Clip",
                    message: message,
                    onRetry: { viewModel.retryLoad() }
                )
            case .ready, .preparingVideo, .publishing:
                composer
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("New Clip")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { requestDismiss() }
                    .font(.body.weight(.regular))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.phase == .ready
                || viewModel.phase == .preparingVideo
                || viewModel.phase == .publishing
            {
                publishBar
            }
        }
        .sheet(isPresented: $showsTradePicker) {
            NavigationStack {
                TradePickerView(
                    trades: viewModel.pickerTrades,
                    imagePipeline: imagePipeline,
                    isLoading: viewModel.isLoadingTrades,
                    onSelect: { trade in
                        viewModel.selectLinkedTrade(trade)
                        showsTradePicker = false
                    },
                    onClose: { showsTradePicker = false }
                )
            }
            .experienceSheetChrome()
            .onAppear { viewModel.loadTradesIfNeeded() }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraVideoPicker(
                onPicked: { url in
                    showsCamera = false
                    viewModel.applyLocalVideo(from: url, contentType: "video/quicktime")
                },
                onCancel: { showsCamera = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsPreview) {
            if let url = viewModel.draft?.localVideoURL {
                NavigationStack {
                    VideoPlayer(player: AVPlayer(url: url))
                        .ignoresSafeArea(edges: .bottom)
                        .experienceSwipeToDismiss { showsPreview = false }
                        .experienceNavigationTitle("Preview")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showsPreview = false }
                            }
                        }
                }
            }
        }
        .confirmationDialog(
            "Discard this clip?",
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
        .onChange(of: videoItem) { _, item in
            Task { await loadPickerVideo(item) }
        }
        .accessibilityIdentifier("createReel.root")
    }

    private var composer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                if viewModel.draft == nil {
                    videoPickerPrompt
                } else {
                    selectedVideoPreview
                    captionBlock
                    linkedTradeBlock
                }

                if let formError = viewModel.formError {
                    Text(formError)
                        .experienceStyle(.footnote, color: colors.loss)
                        .accessibilityIdentifier("createReel.formError")
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.sm)
            .padding(.bottom, ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(viewModel.phase == .publishing)
    }

    private var videoPickerPrompt: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if viewModel.isPreparingVideo {
                HStack(spacing: ExperienceSpacing.sm) {
                    ProgressView()
                    Text("Preparing video…")
                        .experienceStyle(.body, color: colors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, ExperienceSpacing.sm)
            } else {
                HStack(spacing: ExperienceSpacing.sm) {
                    PhotosPicker(selection: $videoItem, matching: .videos) {
                        CreateComposerAttachmentAction(
                            systemImage: "video",
                            title: "Choose Video"
                        )
                    }
                    .disabled(viewModel.phase == .publishing)
                    .accessibilityIdentifier("createReel.chooseVideo")

                    Spacer(minLength: 0)

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showsCamera = true
                        } label: {
                            Text("Record")
                                .font(ExperienceTypography.subheadline.weight(.semibold))
                                .foregroundStyle(colors.secondaryText)
                        }
                        .accessibilityIdentifier("createReel.record")
                    }
                }
                .padding(.top, ExperienceSpacing.xxs)

                Text("MP4 or MOV · max 90s · 100 MB")
                    .experienceStyle(.caption, color: colors.tertiaryText)
                    .padding(.leading, 2)
            }
        }
    }

    @ViewBuilder
    private var selectedVideoPreview: some View {
        if let draft = viewModel.draft, let thumb = draft.thumbnailPreview {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                ZStack(alignment: .topTrailing) {
                    Button {
                        showsPreview = true
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: 240)
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
                                .overlay {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 44))
                                        .foregroundStyle(.white.opacity(0.92))
                                        .shadow(radius: 4)
                                }

                            Text(draft.formattedDuration)
                                .experienceStyle(.caption, color: .white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.55), in: Capsule())
                                .padding(ExperienceSpacing.sm)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play clip preview")

                    CreateComposerPreviewDismissButton(accessibilityLabel: "Remove video") {
                        viewModel.clearVideo()
                        videoItem = nil
                    }
                    .padding(ExperienceSpacing.sm)
                }

                HStack(spacing: ExperienceSpacing.md) {
                    PhotosPicker(selection: $videoItem, matching: .videos) {
                        Text("Change")
                            .font(ExperienceTypography.subheadline.weight(.semibold))
                            .foregroundStyle(colors.accent)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var captionBlock: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            CreateComposerSectionLabel(title: "Caption")

            if viewModel.captionEnabled {
                CreateComposerMultilineField(
                    text: $viewModel.captionText,
                    placeholder: "Write something about this clip…",
                    minHeight: 72,
                    accessibilityIdentifier: "createReel.caption",
                    accessibilityLabel: "Clip caption"
                )
                Text("\(viewModel.captionText.count)/\(MediaVideoPreparation.maxCaptionLength)")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            } else {
                Text("Caption comes from the linked trade’s public description.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
    }

    private var linkedTradeBlock: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            CreateComposerSectionLabel(title: "Linked trade")

            if let trade = viewModel.linkedTrade {
                LinkedTradePreviewCard(
                    trade: trade,
                    imagePipeline: imagePipeline,
                    onChange: { showsTradePicker = true },
                    onRemove: { viewModel.clearLinkedTrade() }
                )
                .accessibilityIdentifier("createReel.linkedTrade")
            } else if viewModel.linkedTradeSummary != nil {
                // Summary without resolved trade — legacy/dev fallback.
                HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.linkedTradeSummary ?? "")
                            .experienceStyle(.body, color: colors.primaryText)
                        Text("Clip description uses this trade")
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                    Spacer(minLength: ExperienceSpacing.xs)
                    Button("Remove") {
                        viewModel.clearLinkedTrade()
                    }
                    .font(ExperienceTypography.subheadline.weight(.semibold))
                    .foregroundStyle(colors.loss)
                }
                .padding(ExperienceSpacing.sm)
                .background(
                    colors.surfaceSecondary,
                    in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                )
                .accessibilityIdentifier("createReel.linkedTrade")
            } else {
                Button {
                    showsTradePicker = true
                } label: {
                    HStack(spacing: ExperienceSpacing.sm) {
                        Image(systemName: "link")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(colors.accent)
                        Text("Link trade")
                            .experienceStyle(.body, color: colors.primaryText)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(colors.tertiaryText)
                    }
                    .padding(.vertical, ExperienceSpacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("createReel.linkTrade")
            }
        }
    }

    private var publishBar: some View {
        CreateComposerPublishBar(
            title: "Post Clip",
            loadingTitle: "Publishing…",
            progress: viewModel.phase == .publishing ? viewModel.uploadProgress : nil,
            isEnabled: viewModel.canPublish && viewModel.draft != nil,
            isLoading: viewModel.phase == .publishing,
            accessibilityIdentifier: "createReel.publish"
        ) {
            viewModel.publish()
        }
    }

    private func requestDismiss() {
        if viewModel.hasUnsavedChanges {
            showsDiscardConfirm = true
        } else {
            viewModel.dismissRequested()
        }
    }

    private func loadPickerVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let movie = try await item.loadTransferable(type: MovieFileTransferable.self) {
                viewModel.applyLocalVideo(from: movie.url, contentType: "video/quicktime")
            } else {
                viewModel.formError = "Couldn't read that video. Try MP4 or MOV."
            }
        } catch {
            viewModel.formError = "Couldn't read that video. Try MP4 or MOV."
        }
    }

    #if DEBUG
    private func applyScreenshotPrefillIfNeeded() {
        guard !didApplyScreenshotPrefill else { return }
        let args = ProcessInfo.processInfo.arguments
        let wantsEmpty = args.contains("-uitesting-create-reel")
        let wantsFilled = args.contains("-uitesting-create-reel-filled")
        guard wantsEmpty || wantsFilled else { return }
        didApplyScreenshotPrefill = true
        viewModel.applyScreenshotFixture(filled: wantsFilled)
    }
    #endif
}
