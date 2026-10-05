import PhotosUI
import SwiftUI
import UIKit

/// Native Create Post — wall post via `profile_posts` (no trade link).
struct CreatePostView: View {
    @State private var viewModel: CreatePostViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var showsDiscardConfirm = false
    @State private var didApplyScreenshotPrefill = false
    @State private var cropSourceImage: UIImage?

    private let imagePipeline: (any ImagePipeline)?

    @Environment(\.themeColors) private var colors
    @FocusState private var isComposerFocused: Bool

    init(
        data: DataEnvironment,
        onDismiss: @escaping () -> Void
    ) {
        imagePipeline = data.imagePipeline
        _viewModel = State(
            initialValue: CreatePostViewModel(
                profiles: data.profiles,
                session: data.session,
                uploadService: data.uploadService,
                objectStorage: data.objectStorage,
                uploadServices: data.globalUploadServices(),
                contentDrafts: data.contentDraftRepository(),
                restoredDraft: ContentDraftLaunchStore.shared.consume(expecting: .post),
                onDismiss: onDismiss
            )
        )
    }

    init(viewModel: CreatePostViewModel) {
        imagePipeline = nil
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
                    title: "Couldn't open New Post",
                    message: message,
                    onRetry: { viewModel.retryLoad() }
                )
            case .ready, .publishing:
                composerContent
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("New Post")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { requestDismiss() }
                    .font(.body.weight(.regular))
            }
            if viewModel.showsSaveDraft {
                ToolbarItem(placement: .primaryAction) {
                    SaveDraftToolbarButton(
                        isSaving: viewModel.isSavingDraft,
                        isEnabled: viewModel.canSaveDraft
                    ) {
                        viewModel.saveDraft()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.phase == .ready || viewModel.phase == .publishing {
                publishBar
            }
        }
        .confirmationDialog(
            "Discard this post?",
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
        .experienceFormKeyboard(isFocused: $isComposerFocused)
        .accessibilityIdentifier("createPost.root")
    }

    private var composerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                composerHeader

                if let preview = viewModel.finalImage {
                    attachedImagePreview(preview)
                }

                if viewModel.finalImage == nil {
                    attachmentToolbar
                }

                if let formError = viewModel.formError {
                    Text(formError)
                        .experienceStyle(.footnote, color: colors.loss)
                        .accessibilityIdentifier("createPost.formError")
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

    private var composerHeader: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            composerAvatar

            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(composerDisplayName)
                        .experienceStyle(.headline, color: colors.primaryText)
                        .lineLimit(1)
                    if !composerUsername.isEmpty {
                        Text("@\(composerUsername)")
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .lineLimit(1)
                    }
                }

                ZStack(alignment: .topLeading) {
                    if viewModel.bodyText.isEmpty {
                        Text("What's on your mind?")
                            .experienceStyle(.body, color: colors.tertiaryText)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $viewModel.bodyText, axis: .vertical)
                        .id("createPostCaption")
                        .focused($isComposerFocused)
                        .font(ExperienceTypography.body)
                        .foregroundStyle(colors.primaryText)
                        .textFieldStyle(.plain)
                        .lineLimit(1...Self.postBodyMaxVisibleLines)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Post text")
                        .accessibilityIdentifier("createPost.body")
                        .experienceTextInputProbe(
                            screen: "createPost",
                            field: "createPost.body",
                            text: viewModel.bodyText,
                            isFocused: isComposerFocused
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Matches prior TextEditor max height (~280pt) — field grows vertically, then scrolls inside.
    private static let postBodyMaxVisibleLines = 14

    @ViewBuilder
    private var composerAvatar: some View {
        if let profile = viewModel.viewerProfile, let imagePipeline {
            FollowListAvatarView(
                profile: profile,
                imagePipeline: imagePipeline,
                size: 36
            )
        } else {
            ExperienceAvatar(
                initials: ProfileDisplay.initials(
                    displayName: composerDisplayName,
                    username: composerUsername
                ),
                size: 36
            )
        }
    }

    private func attachedImagePreview(_ preview: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            AdaptiveMediaPreviewImage(image: preview)
                .clipShape(
                    RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                        .stroke(colors.border.opacity(ExperienceOpacity.subtle), lineWidth: ExperienceBorder.hairline)
                }
                .accessibilityLabel("Post image preview")

            CreateComposerPreviewDismissButton(accessibilityLabel: "Remove image") {
                viewModel.clearImage()
                photoItem = nil
            }
            .padding(ExperienceSpacing.sm)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, 36 + ExperienceSpacing.sm)
    }

    private var attachmentToolbar: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            PhotosPicker(selection: $photoItem, matching: MediaPickerPolicy.imageOnly.matching) {
                CreateComposerAttachmentAction(
                    systemImage: "photo",
                    title: "Add photo"
                )
            }
            .disabled(viewModel.phase == .publishing)
            .accessibilityIdentifier("createPost.media.picker")

            Spacer(minLength: 0)
        }
        .padding(.top, ExperienceSpacing.xxs)
        .padding(.leading, 36 + ExperienceSpacing.sm)
        .overlay(alignment: .top) {
            ExperienceDivider()
                .offset(y: -ExperienceSpacing.sm)
        }
    }

    private var publishBar: some View {
        CreateComposerPublishBar(
            title: "Publish",
            loadingTitle: viewModel.isUploadingMedia ? "Uploading…" : "Publishing…",
            isEnabled: viewModel.hasValidDraft && viewModel.phase == .ready,
            isLoading: viewModel.phase == .publishing,
            accessibilityIdentifier: "createPost.publish"
        ) {
            viewModel.publish()
        }
    }

    private var composerDisplayName: String {
        let name = viewModel.viewerProfile?.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        let username = composerUsername
        return username.isEmpty ? "You" : username
    }

    private var composerUsername: String {
        viewModel.viewerProfile?.username
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
        guard args.contains("-uitesting-create-post-filled") else { return }
        didApplyScreenshotPrefill = true
        viewModel.bodyText = "Great session on MNQ — stuck to the plan and took the A+ setup."
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 360))
        let image = renderer.image { context in
            UIColor(red: 0.06, green: 0.14, blue: 0.24, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
        }
        viewModel.setImage(image)
    }
    #endif
}
