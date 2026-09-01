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
        .experienceNavigationTitle("Create Story")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { requestDismiss() }
                    .disabled(viewModel.phase == .publishing)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.imagePreview != nil {
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
        .experienceSwipeToDismiss { requestDismiss() }
        .interactiveDismissDisabled(viewModel.phase == .publishing)
        .task { viewModel.loadIfNeeded() }
        .onChange(of: photoItem) { _, item in
            Task { await loadPhoto(item) }
        }
        .accessibilityIdentifier("createStory.root")
    }

    private var composeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                Text("Preview how your story will appear before posting.")
                    .experienceStyle(.body, color: colors.secondaryText)

                if let preview = viewModel.imagePreview, let profile = viewModel.viewerProfile {
                    StoryComposePreviewFrame(profile: profile, image: preview)
                        .frame(maxWidth: 274)
                        .frame(maxWidth: .infinity)
                } else {
                    pickerPrompt
                }

                if viewModel.imagePreview != nil {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Change image", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.phase == .publishing)
                    .accessibilityIdentifier("createStory.changeImage")
                }

                if let formError = viewModel.formError {
                    Text(formError)
                        .foregroundStyle(colors.loss)
                        .font(.footnote)
                        .accessibilityIdentifier("createStory.formError")
                }

                if viewModel.phase == .publishing {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                        ProgressView(value: viewModel.uploadProgress)
                        Text(viewModel.uploadStage)
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                    .accessibilityIdentifier("createStory.progress")
                }
            }
            .padding(ExperienceSpacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var pickerPrompt: some View {
        VStack(spacing: ExperienceSpacing.md) {
            ExperienceEmptyState(
                icon: .photo,
                title: "Add a photo",
                message: "Stories use a single image, visible for 24 hours."
            )
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("createStory.media.picker")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ExperienceSpacing.lg)
    }

    private var publishBar: some View {
        VStack(spacing: 0) {
            Divider()
            ExperienceButton(
                title: viewModel.phase == .publishing ? "Posting Story…" : "Post Story",
                kind: .primary,
                isEnabled: viewModel.canPublish && viewModel.phase != .publishing,
                isLoading: viewModel.phase == .publishing,
                accessibilityIdentifier: "createStory.publish"
            ) {
                viewModel.publish()
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
            .background(colors.backgroundPrimary.opacity(0.96))
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
