import PhotosUI
import SwiftUI

/// Native story composer — photo pick → full-screen editor → publish.
struct CreateStoryView: View {
    @State private var viewModel: CreateStoryViewModel
    @State private var photoItem: PhotosPickerItem?
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
        .interactiveDismissDisabled(viewModel.phase == .publishing)
        .task { viewModel.loadIfNeeded() }
        .onChange(of: photoItem) { _, item in
            Task { await loadPhoto(item) }
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
                onCancel: {
                    viewModel.clearImage()
                    photoItem = nil
                },
                onNext: { rendered in
                    viewModel.submitRenderedStory(rendered)
                }
            )
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

                Text("Add a photo to your story")
                    .experienceStyle(.headline, color: colors.primaryText)

                Text("Stories are visible for 24 hours.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, ExperienceSpacing.lg)

            PhotosPicker(selection: $photoItem, matching: .images) {
                CreateComposerAttachmentAction(
                    systemImage: "photo",
                    title: "Choose Photo"
                )
            }
            .disabled(viewModel.phase == .publishing)
            .accessibilityIdentifier("createStory.media.picker")

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
    }

    private var publishingContent: some View {
        VStack(spacing: ExperienceSpacing.md) {
            if let preview = viewModel.imagePreview {
                Image(uiImage: preview)
                    .resizable()
                    .aspectRatio(StoryCanvasState.canvasAspectRatio, contentMode: .fit)
                    .frame(maxWidth: 280)
                    .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
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
        if viewModel.imageData != nil || viewModel.phase == .publishing {
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

    private func requestDismiss() {
        if viewModel.phase == .publishing { return }
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
            viewModel.setSourceImage(image, fileName: "story.jpg")
        } else {
            viewModel.reportPickerError("Couldn't load image.")
        }
    }
}
