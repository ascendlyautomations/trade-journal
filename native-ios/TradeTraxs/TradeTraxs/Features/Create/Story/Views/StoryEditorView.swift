import AVFoundation
import SwiftUI

/// Full-screen Instagram-style story editor — crop/zoom image + text overlays.
struct StoryEditorView: View {
    @State private var viewModel: StoryEditorViewModel
    @FocusState private var textFieldFocused: Bool

    private let isPosting: Bool
    private let isSavingDraft: Bool
    private let onSaveDraft: ((StoryCanvasState) -> Void)?
    private let onCancel: () -> Void
    private let onPostStory: ((UIImage) -> Void)?
    private let onPostVideo: (([StoryTextOverlay]) -> Void)?

    @State private var imageDragStart: CGSize = .zero
    @State private var imagePinchStart: CGFloat?

    @State private var draggingTextOverlayID: UUID?
    @State private var isOverStoryTrashZone = false
    @State private var storyTrashZoneEntered = false

    @Environment(\.themeColors) private var colors

    init(
        sourceImage: UIImage,
        isPosting: Bool = false,
        restoredCanvas: StoryCanvasState? = nil,
        isSavingDraft: Bool = false,
        onSaveDraft: ((StoryCanvasState) -> Void)? = nil,
        onCancel: @escaping () -> Void,
        onPostStory: @escaping (UIImage) -> Void
    ) {
        let editor = StoryEditorViewModel(sourceImage: sourceImage)
        if let restoredCanvas {
            editor.applyRestoredCanvas(restoredCanvas)
        }
        _viewModel = State(initialValue: editor)
        self.isPosting = isPosting
        self.isSavingDraft = isSavingDraft
        self.onSaveDraft = onSaveDraft
        self.onCancel = onCancel
        self.onPostStory = onPostStory
        self.onPostVideo = nil
    }

    init(
        videoURL: URL,
        isPosting: Bool = false,
        restoredCanvas: StoryCanvasState? = nil,
        isSavingDraft: Bool = false,
        onSaveDraft: ((StoryCanvasState) -> Void)? = nil,
        onCancel: @escaping () -> Void,
        onPostVideo: @escaping ([StoryTextOverlay]) -> Void
    ) {
        let editor = StoryEditorViewModel(videoURL: videoURL)
        if let restoredCanvas {
            editor.applyRestoredCanvas(restoredCanvas)
        }
        _viewModel = State(initialValue: editor)
        self.isPosting = isPosting
        self.isSavingDraft = isSavingDraft
        self.onSaveDraft = onSaveDraft
        self.onCancel = onCancel
        self.onPostStory = nil
        self.onPostVideo = onPostVideo
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.top, ExperienceSpacing.sm)

            Spacer(minLength: ExperienceSpacing.sm)

            storyCanvas
                .padding(.horizontal, ExperienceSpacing.md)

            Spacer(minLength: ExperienceSpacing.sm)

            if viewModel.isEditingText {
                textEditingChrome
            } else {
                bottomBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .experienceScreenBackground()
        .experienceFormFocusSync($textFieldFocused)
        .accessibilityIdentifier("storyEditor.root")
    }

    private var topBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(.body.weight(.regular))
                .foregroundStyle(colors.primaryText)
                .accessibilityIdentifier("storyEditor.cancel")

            Spacer()

            if onSaveDraft != nil {
                Button {
                    onSaveDraft?(viewModel.canvas)
                } label: {
                    if isSavingDraft {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save Draft")
                            .font(.subheadline.weight(.regular))
                    }
                }
                .font(.subheadline.weight(.regular))
                .foregroundStyle(colors.primaryText)
                .disabled(isSavingDraft || isPosting)
                .accessibilityIdentifier("composer.saveDraft")
            }

            Button {
                viewModel.beginAddingText()
                textFieldFocused = true
            } label: {
                Text("Aa")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(colors.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("storyEditor.addText")
        }
    }

    private var storyTrashDeleteTarget: some View {
        Image(systemName: "trash.fill")
            .font(.system(size: isOverStoryTrashZone ? 22 : 18, weight: .semibold))
            .foregroundStyle(isOverStoryTrashZone ? colors.textInverse : colors.primaryText)
            .frame(
                width: StoryTextDragDeleteMetrics.iconSize,
                height: StoryTextDragDeleteMetrics.iconSize
            )
            .background(
                Circle()
                    .fill(isOverStoryTrashZone ? colors.loss : colors.surfaceSecondary.opacity(0.92))
            )
            .overlay {
                Circle()
                    .stroke(isOverStoryTrashZone ? colors.loss : colors.border, lineWidth: isOverStoryTrashZone ? 3 : 1)
            }
            .scaleEffect(isOverStoryTrashZone ? 1.18 : 1)
            .animation(.easeOut(duration: 0.15), value: isOverStoryTrashZone)
            .allowsHitTesting(false)
            .accessibilityLabel("Delete text overlay")
            .accessibilityIdentifier("storyEditor.trashTarget")
    }

    private var bottomBar: some View {
        ExperienceButton(
            title: "Post Story",
            kind: .primary,
            isEnabled: !isPosting,
            isLoading: isPosting,
            accessibilityIdentifier: "storyEditor.postStory"
        ) {
            if let onPostVideo {
                onPostVideo(viewModel.publishableTextOverlays)
                return
            }
            guard let rendered = viewModel.renderFinalImage() else { return }
            onPostStory?(rendered)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.md)
    }

    private var storyCanvas: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            ZStack {
                Color.black

                imageLayer(canvasSize: canvasSize)

                ForEach(viewModel.canvas.textOverlays) { overlay in
                    StoryTextOverlayView(
                        overlay: overlay,
                        canvasSize: canvasSize,
                        isSelected: viewModel.canvas.selectedTextID == overlay.id,
                        transformsEnabled: !viewModel.isEditingText,
                        onSelect: {
                            viewModel.selectText(overlay.id)
                        },
                        onMove: { center in
                            viewModel.updateOverlayPosition(id: overlay.id, normalizedCenter: center)
                        },
                        onScale: { scale in
                            viewModel.updateOverlayScale(id: overlay.id, scale: scale)
                        },
                        onRotation: { radians in
                            viewModel.updateOverlayRotation(id: overlay.id, radians: radians)
                        },
                        onEdit: {
                            viewModel.selectText(overlay.id)
                            viewModel.beginEditingSelectedText()
                            textFieldFocused = true
                        },
                        onOverlayDragBegan: {
                            draggingTextOverlayID = overlay.id
                            storyTrashZoneEntered = false
                            isOverStoryTrashZone = false
                        },
                        onOverlayDragLocation: { center in
                            guard draggingTextOverlayID == overlay.id else { return }
                            updateTrashHover(center: center, canvasSize: canvasSize)
                        },
                        onOverlayDragEnded: { center in
                            guard draggingTextOverlayID == overlay.id else { return }
                            if StoryTextDragDeleteMetrics.containsElementCenter(center, canvasSize: canvasSize) {
                                viewModel.deleteOverlay(id: overlay.id)
                            }
                            draggingTextOverlayID = nil
                            isOverStoryTrashZone = false
                            storyTrashZoneEntered = false
                        }
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                    .stroke(
                        colors.border.opacity(ExperienceOpacity.subtle),
                        lineWidth: ExperienceBorder.hairline
                    )
            }
            .experienceElevation(.low)
            .overlay(alignment: .topTrailing) {
                if draggingTextOverlayID != nil {
                    storyTrashDeleteTarget
                        .padding(.top, StoryTextDragDeleteMetrics.canvasInset)
                        .padding(.trailing, StoryTextDragDeleteMetrics.canvasInset)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !viewModel.isEditingText {
                    viewModel.selectText(nil)
                }
            }
            .onAppear {
                viewModel.updateCanvasSize(canvasSize)
            }
            .onChange(of: canvasSize) { _, newSize in
                viewModel.updateCanvasSize(newSize)
            }
        }
        .aspectRatio(StoryCanvasState.canvasAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func imageLayer(canvasSize: CGSize) -> some View {
        if let sourceImage = viewModel.sourceImage {
            let rect = StoryImageLayout.drawRect(
                imageSize: sourceImage.size,
                canvasSize: canvasSize,
                scale: viewModel.canvas.imageScale,
                offset: viewModel.canvas.imageOffset
            )

            Image(uiImage: sourceImage)
                .resizable()
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .gesture(imageDragGesture(canvasSize: canvasSize))
                .simultaneousGesture(imagePinchGesture(canvasSize: canvasSize))
                .allowsHitTesting(viewModel.canvas.selectedTextID == nil && !viewModel.isEditingText)
        } else if let videoURL = viewModel.videoURL {
            StoryEditorLoopingVideo(url: videoURL)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .clipped()
                .allowsHitTesting(false)
        }
    }

    private func imageDragGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if imageDragStart == .zero {
                    imageDragStart = viewModel.canvas.imageOffset
                }
                let proposed = CGSize(
                    width: imageDragStart.width + value.translation.width,
                    height: imageDragStart.height + value.translation.height
                )
                viewModel.updateImageOffset(proposed)
            }
            .onEnded { _ in
                imageDragStart = .zero
            }
    }

    private func imagePinchGesture(canvasSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if imagePinchStart == nil {
                    imagePinchStart = viewModel.canvas.imageScale
                }
                viewModel.updateImageScale((imagePinchStart ?? viewModel.canvas.imageScale) * value)
            }
            .onEnded { _ in
                imagePinchStart = nil
            }
    }

    private var textEditingChrome: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.sm) {
                ForEach(StoryTextColor.allCases) { color in
                    Circle()
                        .fill(color.swiftUIColor)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(
                                    colors.accent,
                                    lineWidth: viewModel.selectedTextFill.matchesPreset(color) ? 2 : 0
                                )
                        )
                        .onTapGesture { viewModel.setSelectedColor(color) }
                }

                ColorPicker(
                    selection: Binding(
                        get: { viewModel.selectedTextFill.swiftUIColor },
                        set: { viewModel.setCustomTextColor($0) }
                    ),
                    supportsOpacity: true
                ) {
                    ZStack {
                        Circle()
                            .fill(viewModel.selectedTextFill.swiftUIColor)
                            .frame(width: 28, height: 28)
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(colors.textInverse)
                    }
                    .overlay(
                        Circle()
                            .stroke(
                                colors.accent,
                                lineWidth: viewModel.selectedTextFill.isCustomColor ? 2 : 0
                            )
                    )
                }
                .labelsHidden()
                .accessibilityLabel("Custom text color")
                .accessibilityIdentifier("storyEditor.customTextColor")
            }

            HStack(spacing: ExperienceSpacing.md) {
                alignmentButton(.leading, symbol: "text.alignleft")
                alignmentButton(.center, symbol: "text.aligncenter")
                alignmentButton(.trailing, symbol: "text.alignright")

                Toggle(isOn: Binding(
                    get: { viewModel.showsTextBackground },
                    set: { viewModel.setShowsTextBackground($0) }
                )) {
                    Image(systemName: "square.fill.on.square.fill")
                }
                .toggleStyle(.button)
                .tint(colors.accent)

                Button(role: .destructive) {
                    viewModel.deleteSelectedText()
                } label: {
                    Image(systemName: "trash")
                }
            }
            .foregroundStyle(colors.primaryText)

            TextField("Type something…", text: Binding(
                get: { viewModel.draftText },
                set: { viewModel.updateDraftText($0) }
            ), axis: .vertical)
            .focused($textFieldFocused)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, ExperienceSpacing.md)

            Button("Done") {
                viewModel.finishEditingText()
                textFieldFocused = false
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(colors.accent)
            .padding(.bottom, ExperienceSpacing.md)
        }
        .padding(.top, ExperienceSpacing.sm)
        .background(colors.backgroundElevated.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            ExperienceDivider()
        }
    }

    private func alignmentButton(_ alignment: TextAlignment, symbol: String) -> some View {
        Button {
            viewModel.setSelectedAlignment(alignment)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(viewModel.selectedAlignment == alignment ? .bold : .regular))
                .foregroundStyle(
                    viewModel.selectedAlignment == alignment ? colors.accent : colors.secondaryText
                )
        }
    }

    private func updateTrashHover(center: CGPoint, canvasSize: CGSize) {
        let overTrash = StoryTextDragDeleteMetrics.containsElementCenter(center, canvasSize: canvasSize)
        if overTrash, !storyTrashZoneEntered {
            ExperienceHaptics.play(.impactLight)
            storyTrashZoneEntered = true
        } else if !overTrash {
            storyTrashZoneEntered = false
        }
        isOverStoryTrashZone = overTrash
    }
}

private enum StoryTextTransformMetrics {
    static let hitPadding: CGFloat = 28
    static let minimumHitSize = CGSize(width: 96, height: 64)
}

/// Trash hit testing in the story canvas coordinate space.
///
/// `DragGesture.location` stays in the overlay's local space after `.position` and
/// `.rotationEffect`, so it cannot be compared with a frame measured on the editor.
/// The element's center uses the same canvas points as `.position`.
enum StoryTextDragDeleteMetrics {
    static let iconSize: CGFloat = 44
    static let canvasInset: CGFloat = 10
    /// Extra space around the visible icon. The element center only needs to enter this zone.
    static let hitOutset: CGFloat = 44

    static func visibleIconFrame(canvasSize: CGSize) -> CGRect {
        CGRect(
            x: canvasSize.width - canvasInset - iconSize,
            y: canvasInset,
            width: iconSize,
            height: iconSize
        )
    }

    static func hitZone(canvasSize: CGSize) -> CGRect {
        visibleIconFrame(canvasSize: canvasSize).insetBy(dx: -hitOutset, dy: -hitOutset)
    }

    static func containsElementCenter(_ center: CGPoint, canvasSize: CGSize) -> Bool {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return false }
        return hitZone(canvasSize: canvasSize).contains(center)
    }
}

struct StoryTextOverlayView: View {
    let overlay: StoryTextOverlay
    let canvasSize: CGSize
    let isSelected: Bool
    let transformsEnabled: Bool
    let onSelect: () -> Void
    let onMove: (CGPoint) -> Void
    let onScale: (CGFloat) -> Void
    let onRotation: (CGFloat) -> Void
    let onEdit: () -> Void
    var onOverlayDragBegan: (() -> Void)?
    var onOverlayDragLocation: ((CGPoint) -> Void)?
    var onOverlayDragEnded: ((CGPoint) -> Void)?

    @State private var dragStartCenter: CGPoint?
    @State private var scaleStart: CGFloat?
    @State private var rotationStart: CGFloat?
    @State private var measuredTextSize: CGSize = .zero

    @Environment(\.themeColors) private var colors

    var body: some View {
        let center = CGPoint(
            x: overlay.normalizedCenter.x * canvasSize.width,
            y: overlay.normalizedCenter.y * canvasSize.height
        )
        let baseFontSize = max(18, canvasSize.width * 0.065) * overlay.scale
        let hitSize = manipulationHitSize

        ZStack {
            Text(overlay.text.isEmpty ? " " : overlay.text)
                .font(.system(size: baseFontSize, weight: .semibold))
                .foregroundStyle(overlay.textFill.swiftUIColor)
                .multilineTextAlignment(overlay.alignment)
                .padding(overlay.showsBackground ? 8 : 0)
                .background {
                    if overlay.showsBackground {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                    }
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { measuredTextSize = proxy.size }
                            .onChange(of: proxy.size) { _, newSize in
                                measuredTextSize = newSize
                            }
                            .onChange(of: overlay.text) { _, _ in
                                measuredTextSize = proxy.size
                            }
                            .onChange(of: overlay.scale) { _, _ in
                                measuredTextSize = proxy.size
                            }
                    }
                }
        }
        .frame(width: hitSize.width, height: hitSize.height)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if isSelected, transformsEnabled {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(colors.accent, lineWidth: ExperienceBorder.thin)
            }
        }
        .rotationEffect(.radians(Double(overlay.rotationRadians)))
        .position(center)
        .highPriorityGesture(transformsEnabled ? dragGesture : nil)
        .simultaneousGesture(transformsEnabled && isSelected ? pinchGesture : nil)
        .simultaneousGesture(transformsEnabled && isSelected ? rotationGesture : nil)
        .simultaneousGesture(
            transformsEnabled
                ? TapGesture(count: 2).onEnded { onEdit() }
                : nil
        )
    }

    private var manipulationHitSize: CGSize {
        let padded = CGSize(
            width: measuredTextSize.width + StoryTextTransformMetrics.hitPadding * 2,
            height: measuredTextSize.height + StoryTextTransformMetrics.hitPadding * 2
        )
        return CGSize(
            width: max(padded.width, StoryTextTransformMetrics.minimumHitSize.width),
            height: max(padded.height, StoryTextTransformMetrics.minimumHitSize.height)
        )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                onSelect()
                if dragStartCenter == nil {
                    dragStartCenter = overlay.normalizedCenter
                    onOverlayDragBegan?()
                }
                guard let start = dragStartCenter else { return }
                let clamped = clampedNormalizedCenter(
                    CGPoint(
                        x: start.x + value.translation.width / max(canvasSize.width, 1),
                        y: start.y + value.translation.height / max(canvasSize.height, 1)
                    )
                )
                onMove(clamped)
                onOverlayDragLocation?(canvasPoint(for: clamped))
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height) >= 4
                if let start = dragStartCenter, moved {
                    let clamped = clampedNormalizedCenter(
                        CGPoint(
                            x: start.x + value.translation.width / max(canvasSize.width, 1),
                            y: start.y + value.translation.height / max(canvasSize.height, 1)
                        )
                    )
                    onOverlayDragEnded?(canvasPoint(for: clamped))
                } else {
                    onSelect()
                }
                dragStartCenter = nil
            }
    }

    private func canvasPoint(for normalizedCenter: CGPoint) -> CGPoint {
        CGPoint(
            x: normalizedCenter.x * canvasSize.width,
            y: normalizedCenter.y * canvasSize.height
        )
    }

    /// Keeps a usable portion of the element on canvas without locking the center away from edges.
    private func clampedNormalizedCenter(_ center: CGPoint) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return center }
        let bounds = manipulationHitSize
        let halfWidthNorm = bounds.width / CGFloat(2) / CGFloat(canvasSize.width)
        let halfHeightNorm = bounds.height / CGFloat(2) / CGFloat(canvasSize.height)
        let offscreenAllowance: CGFloat = 0.88
        let minX = -halfWidthNorm * offscreenAllowance
        let maxX = CGFloat(1) + halfWidthNorm * offscreenAllowance
        let minY = -halfHeightNorm * offscreenAllowance
        let maxY = CGFloat(1) + halfHeightNorm * offscreenAllowance
        return CGPoint(
            x: min(max(center.x, minX), maxX),
            y: min(max(center.y, minY), maxY)
        )
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                onSelect()
                if scaleStart == nil {
                    scaleStart = overlay.scale
                }
                onScale((scaleStart ?? overlay.scale) * value)
            }
            .onEnded { _ in
                scaleStart = nil
            }
    }

    private var rotationGesture: some Gesture {
        RotationGesture()
            .onChanged { angle in
                onSelect()
                if rotationStart == nil {
                    rotationStart = overlay.rotationRadians
                }
                onRotation((rotationStart ?? overlay.rotationRadians) + angle.radians)
            }
            .onEnded { _ in
                rotationStart = nil
            }
    }
}

/// Aspect-fills the story canvas and keeps the clip looping under the text editor.
private struct StoryEditorLoopingVideo: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIView(context: Context) -> FeedPlayerLayerView {
        let view = FeedPlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        view.playerLayer.player = context.coordinator.player
        context.coordinator.player.play()
        return view
    }

    func updateUIView(_ uiView: FeedPlayerLayerView, context: Context) {
        uiView.playerLayer.videoGravity = .resizeAspectFill
        uiView.playerLayer.player = context.coordinator.player
        if context.coordinator.player.rate == 0 {
            context.coordinator.player.play()
        }
    }

    static func dismantleUIView(_ uiView: FeedPlayerLayerView, coordinator: Coordinator) {
        coordinator.player.pause()
        uiView.playerLayer.player = nil
    }

    final class Coordinator {
        let player: AVQueuePlayer
        private let looper: AVPlayerLooper

        init(url: URL) {
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer()
            player = queue
            looper = AVPlayerLooper(player: queue, templateItem: item)
        }
    }
}
