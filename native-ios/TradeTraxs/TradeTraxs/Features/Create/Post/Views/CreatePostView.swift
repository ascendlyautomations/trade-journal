import PhotosUI
import SwiftUI
import UIKit

/// Native Create Post — wall post via `profile_posts` (no trade link).
struct CreatePostView: View {
    @State private var viewModel: CreatePostViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var showsDiscardConfirm = false
    @State private var didApplyScreenshotPrefill = false

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        onDismiss: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: CreatePostViewModel(
                profiles: data.profiles,
                session: data.session,
                uploadService: data.uploadService,
                objectStorage: data.objectStorage,
                onDismiss: onDismiss
            )
        )
    }

    init(viewModel: CreatePostViewModel) {
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
                formContent
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("New Post")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { requestDismiss() }
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
        .accessibilityIdentifier("createPost.root")
    }

    private var formContent: some View {
        Form {
            Section("Post") {
                TextEditor(text: $viewModel.bodyText)
                    .frame(minHeight: 140)
                    .accessibilityLabel("Post text")
                    .accessibilityIdentifier("createPost.body")
            }

            Section("Image") {
                if let preview = viewModel.imagePreview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                        .accessibilityLabel("Post image preview")
                    Button("Remove Image", role: .destructive) {
                        viewModel.clearImage()
                        photoItem = nil
                    }
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(imagePickerTitle, systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("createPost.media.picker")
            }

            if let formError = viewModel.formError {
                Section {
                    Text(formError)
                        .foregroundStyle(colors.loss)
                        .font(.footnote)
                        .accessibilityIdentifier("createPost.formError")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .disabled(viewModel.phase == .publishing)
    }

    private var imagePickerTitle: String {
        viewModel.imagePreview == nil ? "Add Image" : "Replace Image"
    }

    private var publishBar: some View {
        VStack(spacing: 0) {
            Divider()
            ExperienceButton(
                title: viewModel.phase == .publishing
                    ? (viewModel.isUploadingMedia ? "Uploading…" : "Publishing…")
                    : "Publish",
                kind: .primary,
                isEnabled: viewModel.canPublish && viewModel.phase != .publishing,
                isLoading: viewModel.phase == .publishing,
                accessibilityIdentifier: "createPost.publish"
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
