import AVKit
import PhotosUI
import SwiftUI
import UIKit

/// Native story composer — photo or short video → publish.
struct CreateStoryView: View {
    @State private var viewModel: CreateStoryViewModel
    @State private var mediaItem: PhotosPickerItem?
    @State private var showsMediaPicker = false
    @State private var showsStoryCamera = false
    @State private var didAutoPresentPhotoPicker = false
    @State private var showsDiscardConfirm = false

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        onPublished: @escaping (Story) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: CreateStoryViewModel(
                feed: data.feed,
                profiles: data.profiles,
                session: data.session,
                detailCache: data.detailCache,
                uploadService: data.uploadService,
                objectStorage: data.objectStorage,
                uploadServices: data.globalUploadServices(),
                onPublished: onPublished,
                onDismiss: onDismiss
            )
        )
    }

    init(viewModel: CreateStoryViewModel) {
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
                    title: "Couldn't open Story",
                    message: message,
                    onRetry: { viewModel.retryLoad() }
                )
            case .ready, .publishing:
                composeContent
            }
        }
        .experienceScreenBackground()
        .toolbar {
            if !showsEditor {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { requestDismiss() }
                        .font(.body.weight(.regular))
                        .disabled(viewModel.phase == .publishing)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !showsEditor {
                publishBar
            }
        }
        .confirmationDialog(
            "Discard this story?",
            isPresented: $showsDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { viewModel.dismissRequested() }
            Button("Keep Editing", role: .cancel) {}
        }
        .experienceProtectedFormDismiss()
        .task { viewModel.loadIfNeeded() }
        .photosPicker(
            isPresented: $showsMediaPicker,
            selection: $mediaItem,
            matching: MediaPickerPolicy.storyMedia.matching
        )
        .onChange(of: mediaItem) { _, item in
            Task { await loadPickedMedia(item) }
        }
        .onChange(of: viewModel.phase) { _, phase in
            if phase == .ready {
                autoPresentMediaPickerIfNeeded()
            }
        }
        .fullScreenCover(isPresented: $showsStoryCamera) {
            CameraStoryPicker(
                onPickedPhoto: { image in
                    showsStoryCamera = false
                    viewModel.setSourceImage(image)
                },
                onPickedVideo: { url in
                    showsStoryCamera = false
                    Task { await viewModel.setSourceVideo(fileURL: url) }
                },
                onCancel: { showsStoryCamera = false }
            )
            .ignoresSafeArea()
        }
        .accessibilityIdentifier("createStory.root")
    }

    private var showsEditor: Bool {
        viewModel.sourceImage != nil && viewModel.imageData == nil && viewModel.phase != .publishing
    }

    @ViewBuilder
    private var composeContent: some View {
        if showsEditor, let source = viewModel.sourceImage {
            StoryEditorView(
                sourceImage: source,
                isPosting: viewModel.isPostingStory,
                onCancel: {
                    viewModel.clearImage()
                    mediaItem = nil
                },
                onPostStory: { rendered in
                    viewModel.postRenderedStory(rendered)
                }
            )
        } else if viewModel.localVideoFileURL != nil && viewModel.imagePreview == nil && viewModel.phase != .publishing {
            videoReadyContent
        } else if viewModel.imagePreview == nil && viewModel.phase != .publishing {
            emptyComposer
        } else {
            publishingContent
        }
    }

    private var emptyComposer: some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer(minLength: ExperienceSpacing.xl)

            VStack(spacing: ExperienceSpacing.sm) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(colors.accent)

                Text("Add a photo or video to your story")
                    .experienceStyle(.headline, color: colors.primaryText)

                Text("Stories are visible for 24 hours. Videos can be up to 10 seconds.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, ExperienceSpacing.lg)

            HStack(spacing: ExperienceSpacing.sm) {
                Button {
                    showsMediaPicker = true
                } label: {
                    CreateComposerAttachmentAction(
                        systemImage: "photo.on.rectangle",
                        title: "Choose Media"
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.phase == .publishing)
                .accessibilityIdentifier("createStory.media.picker")

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showsStoryCamera = true
                    } label: {
                        CreateComposerAttachmentAction(
                            systemImage: "camera",
                            title: "Camera"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.phase == .publishing)
                    .accessibilityIdentifier("createStory.media.camera")
                }
            }

            if let formError = viewModel.formError {
                Text(formError)
                    .experienceStyle(.footnote, color: colors.loss)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .accessibilityIdentifier("createStory.formError")
            }

            Spacer(minLength: ExperienceSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, ExperienceSpacing.md)
        .onAppear {
            autoPresentMediaPickerIfNeeded()
        }
    }

    private var videoReadyContent: some View {
        VStack(spacing: ExperienceSpacing.md) {
            if let url = viewModel.localVideoFileURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .aspectRatio(StoryCanvasState.canvasAspectRatio, contentMode: .fit)
                    .frame(maxWidth: 280)
                    .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
                    .accessibilityIdentifier("createStory.videoPreview")
            }

            Button("Choose Different Media") {
                viewModel.clearImage()
                mediaItem = nil
                showsMediaPicker = true
            }
            .font(ExperienceTypography.subheadline.weight(.semibold))
            .foregroundStyle(colors.accent)

            if let formError = viewModel.formError {
                Text(formError)
                    .experienceStyle(.footnote, color: colors.loss)
                    .accessibilityIdentifier("createStory.formError")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, ExperienceSpacing.lg)
    }

    private var publishingContent: some View {
        VStack(spacing: ExperienceSpacing.md) {
            if let preview = viewModel.imagePreview {
                Image(uiImage: preview)
                    .resizable()
                    .aspectRatio(StoryCanvasState.canvasAspectRatio, contentMode: .fit)
                    .frame(maxWidth: 280)
                    .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                            .stroke(
                                colors.border.opacity(ExperienceOpacity.subtle),
                                lineWidth: ExperienceBorder.hairline
                            )
                    }
                    .experienceElevation(.low)
                    .accessibilityIdentifier("createStory.preview")
            }

            if viewModel.phase == .publishing {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    ProgressView(value: viewModel.uploadProgress)
                    Text(viewModel.uploadStage)
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ExperienceSpacing.md)
                .accessibilityIdentifier("createStory.progress")
            }

            if let formError = viewModel.formError {
                Text(formError)
                    .experienceStyle(.footnote, color: colors.loss)
                    .accessibilityIdentifier("createStory.formError")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, ExperienceSpacing.lg)
    }

    @ViewBuilder
    private var publishBar: some View {
        if viewModel.canPublish || viewModel.phase == .publishing {
            CreateComposerPublishBar(
                title: "Post Story",
                loadingTitle: "Posting Story…",
                progress: viewModel.phase == .publishing ? viewModel.uploadProgress : nil,
                isEnabled: viewModel.canPublish,
                isLoading: viewModel.phase == .publishing,
                accessibilityIdentifier: "createStory.publish"
            ) {
                viewModel.publish()
            }
        }
    }

    private func autoPresentMediaPickerIfNeeded() {
        guard !didAutoPresentPhotoPicker else { return }
        guard viewModel.phase == .ready else { return }
        guard viewModel.sourceImage == nil,
              viewModel.imagePreview == nil,
              viewModel.localVideoFileURL == nil
        else { return }
        didAutoPresentPhotoPicker = true
        showsMediaPicker = true
    }

    private func requestDismiss() {
        if viewModel.phase == .publishing { return }
        if viewModel.hasUnsavedChanges {
            showsDiscardConfirm = true
        } else {
            viewModel.dismissRequested()
        }
    }

    private func loadPickedMedia(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        mediaItem = nil
        if item.isVideoPickerItem {
            do {
                guard let movie = try await item.loadTransferable(type: MovieFileTransferable.self) else {
                    viewModel.reportPickerError("Couldn't load video.")
                    return
                }
                await viewModel.setSourceVideo(fileURL: movie.url)
            } catch {
                viewModel.reportPickerError(UserFacingError.message(for: error))
            }
            return
        }

        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data)
        {
            viewModel.setSourceImage(image, fileName: "story.jpg")
        } else if let image = await ImageCropSelectionSupport.loadUIImage(from: item) {
            viewModel.setSourceImage(image, fileName: "story.jpg")
        } else {
            viewModel.reportPickerError("Couldn't load image.")
        }
    }
}
