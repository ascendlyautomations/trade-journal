import PhotosUI
import SwiftUI

/// Native story composer — web `StoryComposeModal` parity (image-only preview + post).
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
        .experienceNavigationTitle("New Story")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { requestDismiss() }
                    .font(.body.weight(.regular))
                    .disabled(viewModel.phase == .publishing)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            publishBar
        }
        .confirmationDialog(
            "Discard this story?",
            isPresented: $showsDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { viewModel.dismissRequested() }
            Button("Keep Editing", role: .cancel) {}
        }
        .experienceSwipeToDismiss { requestDismiss() }
        .interactiveDismissDisabled(viewModel.phase == .publishing)
        .task { viewModel.loadIfNeeded() }
        .onChange(of: photoItem) { _, item in
            Task { await loadPhoto(item) }
        }
        .accessibilityIdentifier("createStory.root")
    }

    @ViewBuilder
    private var composeContent: some View {
        if viewModel.imagePreview == nil {
            emptyComposer
        } else {
            storyPreviewComposer
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

    private var storyPreviewComposer: some View {
        ScrollView {
            VStack(spacing: ExperienceSpacing.md) {
                if let preview = viewModel.imagePreview, let profile = viewModel.viewerProfile {
                    ZStack(alignment: .topTrailing) {
                        StoryComposePreviewFrame(profile: profile, image: preview)
                            .frame(maxWidth: 300)
                            .frame(maxWidth: .infinity)

                        CreateComposerPreviewDismissButton(accessibilityLabel: "Remove story photo") {
                            viewModel.clearImage()
                            photoItem = nil
                        }
                        .padding(ExperienceSpacing.sm)
                    }
                }

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text("Change photo")
                        .font(ExperienceTypography.subheadline.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }
                .disabled(viewModel.phase == .publishing)
                .accessibilityIdentifier("createStory.changeImage")

                if viewModel.phase == .publishing {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                        ProgressView(value: viewModel.uploadProgress)
                        Text(viewModel.uploadStage)
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("createStory.progress")
                }

                if let formError = viewModel.formError {
                    Text(formError)
                        .experienceStyle(.footnote, color: colors.loss)
                        .accessibilityIdentifier("createStory.formError")
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.sm)
            .padding(.bottom, ExperienceSpacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var publishBar: some View {
        if viewModel.imagePreview != nil || viewModel.phase == .publishing {
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
            viewModel.setImage(image, fileName: "story.jpg")
        } else {
            viewModel.reportPickerError("Couldn't load image.")
        }
    }
}

/// Story phone-frame preview — web `StoryFrame` layout.
private struct StoryComposePreviewFrame: View {
    let profile: Profile
    let image: UIImage

    private var displayName: String {
        let username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !username.isEmpty { return username }
        return profile.displayName
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color(red: 0.06, green: 0.09, blue: 0.16)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 44)
                    .accessibilityLabel("Story preview")

                HStack(spacing: ExperienceSpacing.sm) {
                    ExperienceAvatar(
                        initials: String(displayName.prefix(2)).uppercased(),
                        size: 32
                    )
                    Text(displayName)
                        .experienceStyle(.headline, color: .white)
                        .lineLimit(1)
                    Text("• Now")
                        .experienceStyle(.caption, color: .white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        }
        .aspectRatio(400 / 700, contentMode: .fit)
        .accessibilityIdentifier("createStory.preview")
    }
}
