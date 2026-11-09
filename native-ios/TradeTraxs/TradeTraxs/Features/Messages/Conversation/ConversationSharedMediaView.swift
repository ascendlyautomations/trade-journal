import SwiftUI

struct ConversationSharedMediaView: View {
    @Bindable var viewModel: ConversationSharedMediaViewModel
    let imagePipeline: any ImagePipeline
    var onViewInChat: (MessageID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .idle:
                    ExperienceLoadingSpinner(label: "Loading shared media")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loading where viewModel.items.isEmpty:
                    ExperienceLoadingSpinner(label: "Loading shared media")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ExperienceErrorState(
                        title: "Couldn't load shared media",
                        message: message,
                        onRetry: { Task { await viewModel.retry() } }
                    )
                case .empty:
                    ExperienceEmptyState(
                        icon: .photo,
                        title: "No shared media yet",
                        message: "Photos and shared posts will appear here."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loaded, .loading:
                    gallery
                }
            }
            .experienceScreenBackground()
            .experienceNavigationTitle("Shared Media")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("conversation.sharedMedia.done")
                }
            }
        }
        .task {
            await viewModel.open()
        }
        .fullScreenCover(item: $viewModel.selectedItem) { item in
            ConversationSharedMediaFullscreenView(
                item: item,
                imagePipeline: imagePipeline,
                onViewInChat: {
                    viewModel.selectedItem = nil
                    dismiss()
                    onViewInChat(item.id)
                }
            )
        }
    }

    private var gallery: some View {
        ScrollView {
            LazyVGrid(
                columns: ConversationSharedMediaGalleryLayout.gridColumns,
                spacing: ConversationSharedMediaGalleryLayout.interItemSpacing
            ) {
                ForEach(viewModel.visibleItems) { item in
                    ConversationSharedMediaCell(
                        item: item,
                        imagePipeline: imagePipeline,
                        showsPlaceholder: viewModel.isThumbnailFailed(item),
                        onFailed: { viewModel.markThumbnailFailed(item) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        ExperienceHaptics.play(.selection)
                        viewModel.selectedItem = item
                    }
                    .onAppear {
                        guard item.id == viewModel.visibleItems.last?.id else { return }
                        Task { await viewModel.loadMoreIfNeeded() }
                    }
                }
            }
            .padding(.horizontal, ConversationSharedMediaGalleryLayout.interItemSpacing)
            if viewModel.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ExperienceSpacing.md)
            }
        }
    }
}

private struct ConversationSharedMediaCell: View {
    let item: ConversationSharedMediaItem
    let imagePipeline: any ImagePipeline
    var showsPlaceholder: Bool
    var onFailed: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.themeColors) private var colors
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { cellContent }
            .clipped()
            .accessibilityAddTraits(.isImage)
            .task(id: loadTaskID) {
                await loadThumbnail()
            }
    }

    @ViewBuilder
    private var cellContent: some View {
        if showsPlaceholder {
            ZStack {
                colors.fillPrimary
                ExperienceIcon(icon: .photo, size: .md, color: colors.tertiaryText)
            }
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                colors.fillPrimary
                ProgressView()
            }
        }
    }

    private var loadTaskID: String {
        "\(item.id.rawValue)|\(item.imageURL)"
    }

    private func loadThumbnail() async {
        guard !showsPlaceholder else { return }
        if image != nil { return }
        if let cached = ProfileBrowseMediaDisplayCache.uiImage(
            reference: item.mediaReference,
            purpose: .tradeScreenshot
        ) {
            image = cached
            return
        }
        let pixelBudget = ProfileBrowseMediaLoader.gridPixelBudget(displayScale: displayScale)
        let loaded = await ProfileBrowseMediaLoader.loadUIImage(
            reference: item.mediaReference,
            purpose: .tradeScreenshot,
            maxPixelSize: pixelBudget,
            displayScale: displayScale,
            imagePipeline: imagePipeline,
            existing: image
        )
        if let loaded {
            image = loaded
        } else {
            onFailed()
        }
    }
}

private struct ConversationSharedMediaFullscreenView: View {
    let item: ConversationSharedMediaItem
    let imagePipeline: any ImagePipeline
    var onViewInChat: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var zoomScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZoomableAsyncImageView(
                reference: item.mediaReference,
                purpose: .tradeScreenshot,
                imagePipeline: imagePipeline,
                maxPixelSize: nil,
                zoomScale: $zoomScale
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .experienceNavigationTitle("Photo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("View in Chat") {
                        ExperienceHaptics.play(.selection)
                        onViewInChat()
                    }
                    .accessibilityIdentifier("conversation.sharedMedia.viewInChat")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .experienceSwipeToDismiss(isEnabled: zoomScale <= 1.02) {
                dismiss()
            }
            .interactiveDismissDisabled(zoomScale > 1.02)
        }
    }
}
