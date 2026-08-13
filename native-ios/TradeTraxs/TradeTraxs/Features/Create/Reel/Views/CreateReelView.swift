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

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        onDismiss: @escaping () -> Void
    ) {
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
                    isLoading: viewModel.isLoadingTrades,
                    onSelect: { trade in
                        viewModel.selectLinkedTrade(trade)
                        showsTradePicker = false
                    },
                    onClose: { showsTradePicker = false }
                )
            }
            .presentationDetents([.medium, .large])
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
                videoBlock

                if viewModel.draft != nil {
                    captionBlock
                    linkedTradeBlock
                }

                if let formError = viewModel.formError {
                    Text(formError)
                        .foregroundStyle(colors.loss)
                        .font(.footnote)
                        .accessibilityIdentifier("createReel.formError")
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(viewModel.phase == .publishing)
    }

    private var videoBlock: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("VIDEO")
                .experienceStyle(.caption, color: colors.secondaryText)

            if let draft = viewModel.draft, let thumb = draft.thumbnailPreview {
                ZStack(alignment: .bottomLeading) {
                    Button {
                        showsPreview = true
                    } label: {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 360)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
                            .overlay {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 52))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .shadow(radius: 4)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play clip preview")

                    Text(draft.formattedDuration)
                        .experienceStyle(.caption, color: .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(ExperienceSpacing.sm)
                }

                HStack(spacing: ExperienceSpacing.md) {
                    PhotosPicker(selection: $videoItem, matching: .videos) {
                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button("Remove", role: .destructive) {
                        viewModel.clearVideo()
                        videoItem = nil
                    }
                }
                .font(.subheadline.weight(.semibold))
            } else {
                VStack(spacing: ExperienceSpacing.md) {
                    if viewModel.isPreparingVideo {
                        ProgressView("Preparing video…")
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                    } else {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(colors.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)

                        PhotosPicker(selection: $videoItem, matching: .videos) {
                            Text("Choose Video")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("createReel.chooseVideo")

                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showsCamera = true
                            } label: {
                                Text("Record")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("createReel.record")
                        }
                    }
                }
                .padding(ExperienceSpacing.md)
                .frame(maxWidth: .infinity)
                .background(
                    colors.backgroundSecondary,
                    in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                )
            }

            Text("MP4 or MOV · max 90s · 100 MB")
                .experienceStyle(.caption, color: colors.tertiaryText)
        }
    }

    private var captionBlock: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("CAPTION")
                .experienceStyle(.caption, color: colors.secondaryText)
            if viewModel.captionEnabled {
                TextField(
                    "Write something about this clip…",
                    text: $viewModel.captionText,
                    axis: .vertical
                )
                .lineLimit(3...8)
                .accessibilityIdentifier("createReel.caption")
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
            Text("LINKED TRADE")
                .experienceStyle(.caption, color: colors.secondaryText)
            if let summary = viewModel.linkedTradeSummary {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary)
                            .experienceStyle(.body, color: colors.primaryText)
                        Text("Clip description uses this trade")
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                    Spacer()
                    Button("Remove") { viewModel.clearLinkedTrade() }
                        .font(.subheadline)
                }
                .padding(ExperienceSpacing.sm)
                .background(
                    colors.backgroundSecondary,
                    in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                )
                .accessibilityIdentifier("createReel.linkedTrade")
            } else {
                Button {
                    showsTradePicker = true
                } label: {
                    Label("Link Trade", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("createReel.linkTrade")
            }
        }
    }

    private var publishBar: some View {
        VStack(spacing: 0) {
            Divider()
            if viewModel.phase == .publishing {
                ProgressView(value: viewModel.uploadProgress)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xs)
            }
            ExperienceButton(
                title: viewModel.phase == .publishing ? "Publishing…" : "Post Clip",
                kind: .primary,
                isEnabled: viewModel.canPublish && viewModel.draft != nil && viewModel.phase != .publishing,
                isLoading: viewModel.phase == .publishing,
                accessibilityIdentifier: "createReel.publish"
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
