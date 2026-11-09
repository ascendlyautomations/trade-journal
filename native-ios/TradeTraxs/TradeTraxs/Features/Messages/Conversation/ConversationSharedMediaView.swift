import SwiftUI

struct ConversationSharedMediaView: View {
    @Bindable var viewModel: ConversationSharedMediaViewModel
    let imagePipeline: any ImagePipeline
    var onViewInChat: (MessageID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .idle, .loading where viewModel.items.isEmpty:
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
        .task(id: viewModel.conversationID) {
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
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(viewModel.visibleItems) { item in
                    ConversationSharedMediaCell(
                        item: item,
                        imagePipeline: imagePipeline,
                        showsPlaceholder: viewModel.isThumbnailFailed(item),
                        onFailed: { viewModel.markThumbnailFailed(item) }
                    )
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
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
        ZStack {
            Color.black.opacity(0.2)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if showsPlaceholder {
                ExperienceIcon(icon: .photo, size: .md, color: colors.tertiaryText)
            } else {
                ProgressView()
            }
        }
        .task(id: item.imageURL) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let reference = item.mediaReference
        let pixel = Int(120 * displayScale * 3)
        let request = ImageRequest(
            reference: reference,
            purpose: .tradeScreenshot,
            maxPixelSize: pixel,
            deliveryQuality: .feedDisplay,
            auditSurface: "conversation.sharedMedia",
            auditMediaID: item.id.rawValue
        )
        do {
            let data = try await imagePipeline.data(for: request)
            if let ui = UIImage(data: data) {
                image = ui
            } else {
                onFailed()
            }
        } catch {
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
