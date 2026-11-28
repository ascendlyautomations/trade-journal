import SwiftUI

struct ConversationSharedMediaView: View {
    @Bindable var viewModel: ConversationSharedMediaViewModel
    let imagePipeline: any ImagePipeline
    var onViewInChat: (MessageID) -> Void
    var onOpenSharedTrade: (TradeID, Trade?) -> Void = { _, _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .idle:
                    ExperienceLoadingOverlay(label: "Loading shared media")
                case .loading where viewModel.items.isEmpty:
                    ExperienceLoadingOverlay(label: "Loading shared media")
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
                        previewTrade: viewModel.previewTrade(for: item),
                        showsPlaceholder: viewModel.isThumbnailFailed(item),
                        onFailed: { viewModel.markThumbnailFailed(item) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        ExperienceHaptics.play(.selection)
                        if item.isSharedTrade, let tradeID = item.tradeID {
                            onOpenSharedTrade(tradeID, viewModel.previewTrade(for: item))
                        } else {
                            viewModel.selectedItem = item
                        }
                    }
                    .onAppear {
                        guard item.id == viewModel.visibleItems.last?.id else { return }
                        Task { await viewModel.loadMoreIfNeeded() }
                    }
                }
            }
            .padding(.horizontal, ConversationSharedMediaGalleryLayout.interItemSpacing)
            if viewModel.isLoadingMore {
                ExperienceIndeterminateProgress()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ExperienceSpacing.md)
            }
        }
    }
}

private struct ConversationSharedMediaCell: View {
    let item: ConversationSharedMediaItem
    let imagePipeline: any ImagePipeline
    var previewTrade: Trade?
    var showsPlaceholder: Bool
    var onFailed: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { cellContent }
            .clipped()
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel(accessibilityLabel)
            .task(id: loadTaskID) {
                await loadThumbnail()
            }
    }

    private var accessibilityLabel: String {
        if item.isSharedTrade {
            let pnl = displayPnL.map { TradeDisplay.pnlText($0) } ?? "P and L"
            return "Shared trade, \(pnl)"
        }
        return "Shared photo"
    }

    private var displayPnL: Money? {
        item.tradeTotalPnL ?? previewTrade?.realizedPnL
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
                .overlay(alignment: .bottomLeading) {
                    if item.isSharedTrade, let displayPnL {
                        ConversationSharedMediaTradePnLBadge(pnl: displayPnL)
                    }
                }
        } else {
            ZStack {
                colors.fillPrimary
                ExperienceIndeterminateProgress()
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

private struct ConversationSharedMediaTradePnLBadge: View {
    let pnl: Money

    @Environment(\.experienceTheme) private var theme

    var body: some View {
        Text(TradeDisplay.pnlText(pnl))
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(pnlColor)
            .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
            .padding(6)
            .accessibilityHidden(true)
    }

    private var pnlColor: Color {
        theme.metricColor(
            for: NSDecimalNumber(decimal: pnl.amount).doubleValue
        )
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