import SwiftUI
import UIKit

/// Shared pinch/drag crop editor — exports feed metadata + original, or a baked avatar image.
struct ImageCropEditorView: View {
    let sourceImage: UIImage
    let preset: ImageCropEditorPreset
    let onCancel: () -> Void
    var onConfirmFeed: ((ImageCropSelectionResult) -> Void)?
    var onConfirmBaked: ((UIImage) -> Void)?

    @Environment(\.themeColors) private var colors
    @State private var aspectOption: ImageCropAspectOption
    @State private var transform = ImageCropTransform.default
    @State private var viewportWidth: CGFloat = 0
    @State private var dragStartOffset = CGSize.zero
    @State private var pinchStartZoom: CGFloat = 1
    @State private var isSaving = false

    init(
        sourceImage: UIImage,
        preset: ImageCropEditorPreset,
        onCancel: @escaping () -> Void,
        onConfirmFeed: @escaping (ImageCropSelectionResult) -> Void
    ) {
        self.sourceImage = MediaImageOrientation.normalized(sourceImage)
        self.preset = preset
        self.onCancel = onCancel
        self.onConfirmFeed = onConfirmFeed
        self.onConfirmBaked = nil
        _aspectOption = State(initialValue: preset.defaultAspectOption)
    }

    init(
        sourceImage: UIImage,
        preset: ImageCropEditorPreset,
        onCancel: @escaping () -> Void,
        onConfirmBaked: @escaping (UIImage) -> Void
    ) {
        self.sourceImage = MediaImageOrientation.normalized(sourceImage)
        self.preset = preset
        self.onCancel = onCancel
        self.onConfirmFeed = nil
        self.onConfirmBaked = onConfirmBaked
        _aspectOption = State(initialValue: preset.defaultAspectOption)
    }

    private var imagePixelSize: CGSize {
        MediaImageOrientation.pixelSize(of: sourceImage)
    }

    private var imageAspect: CGFloat {
        MediaImageOrientation.aspectRatio(of: sourceImage)
    }

    private var originalExceedsFeedLimit: Bool {
        FeedMediaLayout.exceedsFeedPortraitLimit(imageAspect: imageAspect)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                Text(preset.subtitle)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if preset.allowedAspectOptions.count > 1 {
                    aspectPicker
                }

                cropViewport
                    .frame(maxWidth: .infinity)

                if allowsReposition {
                    Text("This is how your image will appear in the Feed.")
                        .experienceStyle(.caption, color: colors.secondaryText)
                    zoomControl
                    Text("Drag to reposition. Pinch or use the slider to zoom.")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                } else {
                    Text("The entire image will appear in your post.")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.sm)
            .experienceScreenBackground()
            .navigationTitle(preset.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Photo") {
                        Task { await confirmCrop() }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            transform = .default
                            dragStartOffset = .zero
                            pinchStartZoom = 1
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(true)
        .accessibilityIdentifier("imageCrop.editor")
    }

    private var allowsReposition: Bool {
        FeedMediaLayout.requiresFillCrop(
            imageAspect: imageAspect,
            aspectOption: aspectOption
        )
    }

    private var aspectPicker: some View {
        Picker("Aspect", selection: $aspectOption) {
            ForEach(preset.allowedAspectOptions) { option in
                Text(option.pickerLabel(originalExceedsFeedLimit: originalExceedsFeedLimit))
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: aspectOption) { _, _ in
            transform = .default
            dragStartOffset = .zero
            pinchStartZoom = 1
        }
    }

    private var cropViewport: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let frameSize = FeedMediaLayout.editorViewportSize(
                containerWidth: width,
                imagePixelSize: imagePixelSize,
                aspectOption: aspectOption
            )

            cropViewportContent(frameSize: frameSize)
                .onAppear { viewportWidth = width }
                .onChange(of: proxy.size.width) { _, newWidth in
                    viewportWidth = newWidth
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: editorViewportHeightEstimate)
    }

    private var editorViewportHeightEstimate: CGFloat {
        guard viewportWidth > 0 else {
            return UIScreen.main.bounds.width * (5 / 4)
        }
        return FeedMediaLayout.editorViewportSize(
            containerWidth: viewportWidth,
            imagePixelSize: imagePixelSize,
            aspectOption: aspectOption
        ).height
    }

    @ViewBuilder
    private func cropViewportContent(frameSize: CGSize) -> some View {
        let width = frameSize.width
        let height = frameSize.height
        let presentation = previewPresentation(containerWidth: width)

        let viewport = ZStack {
            colors.fillSecondary

            if presentation.usesFillCrop,
               let draw = FeedMediaLayout.drawRect(
                imagePixelSize: imagePixelSize,
                frameSize: frameSize,
                presentation: presentation
               ) {
                Image(uiImage: sourceImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: draw.width, height: draw.height)
                    .offset(x: draw.x, y: draw.y)
            } else {
                Image(uiImage: sourceImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width, height: height)
            }

            cropMask(width: width, height: height)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .stroke(colors.accent.opacity(0.85), lineWidth: 1.5)
        }
        .contentShape(Rectangle())

        if allowsReposition {
            viewport
                .gesture(dragGesture(frameSize: frameSize))
                .simultaneousGesture(pinchGesture(frameSize: frameSize))
        } else {
            viewport
        }
    }

    private func previewPresentation(containerWidth: CGFloat) -> ContentImagePresentation {
        let viewport = FeedMediaLayout.editorViewportSize(
            containerWidth: containerWidth,
            imagePixelSize: imagePixelSize,
            aspectOption: aspectOption
        )
        return ContentImagePresentation.make(
            aspectOption: aspectOption,
            imagePixelSize: imagePixelSize,
            viewportSize: viewport,
            transform: transform
        )
    }

    private var zoomControl: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text("Zoom")
                .experienceStyle(.caption, color: colors.secondaryText)
            Slider(
                value: Binding(
                    get: { transform.zoom },
                    set: { newValue in
                        applyTransform(
                            zoom: newValue,
                            offset: transform.offset,
                            frameSize: editorFrameSize
                        )
                    }
                ),
                in: ImageCropMath.minZoom...preset.maxZoom
            )
        }
    }

    private var editorFrameSize: CGSize {
        FeedMediaLayout.editorViewportSize(
            containerWidth: viewportWidth,
            imagePixelSize: imagePixelSize,
            aspectOption: aspectOption
        )
    }

    private func dragGesture(frameSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let next = CGSize(
                    width: dragStartOffset.width + value.translation.width,
                    height: dragStartOffset.height + value.translation.height
                )
                applyTransform(zoom: transform.zoom, offset: next, frameSize: frameSize)
            }
            .onEnded { _ in
                dragStartOffset = transform.offset
            }
    }

    private func pinchGesture(frameSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                applyTransform(
                    zoom: pinchStartZoom * value,
                    offset: transform.offset,
                    frameSize: frameSize
                )
            }
            .onEnded { _ in
                pinchStartZoom = transform.zoom
            }
    }

    private func applyTransform(zoom: CGFloat, offset: CGSize, frameSize: CGSize) {
        let pixelSize = imagePixelSize
        let clampedZoom = ImageCropMath.clampZoom(zoom, maxZoom: preset.maxZoom)
        let clampedOffset = ImageCropMath.clampOffset(
            imageWidth: pixelSize.width,
            imageHeight: pixelSize.height,
            frameWidth: frameSize.width,
            frameHeight: frameSize.height,
            zoom: clampedZoom,
            offset: offset
        )
        transform = ImageCropTransform(zoom: clampedZoom, offset: clampedOffset)
    }

    @ViewBuilder
    private func cropMask(width: CGFloat, height: CGFloat) -> some View {
        switch preset.mask {
        case .none:
            EmptyView()
        case .feedViewport:
            ZStack {
                Color.black.opacity(0.48)
                RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                    .frame(width: width, height: height)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .allowsHitTesting(false)
        case .circle:
            ZStack {
                Color.black.opacity(0.35)
                Circle()
                    .frame(width: min(width, height), height: min(width, height))
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .allowsHitTesting(false)
        }
    }

    private func confirmCrop() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        if let onConfirmFeed {
            let width = max(viewportWidth, 1)
            let viewport = FeedMediaLayout.editorViewportSize(
                containerWidth: width,
                imagePixelSize: imagePixelSize,
                aspectOption: aspectOption
            )
            let presentation = ContentImagePresentation.make(
                aspectOption: aspectOption,
                imagePixelSize: imagePixelSize,
                viewportSize: viewport,
                transform: transform
            )
            onConfirmFeed(
                ImageCropSelectionResult(
                    originalImage: sourceImage,
                    presentation: presentation
                )
            )
            return
        }

        if let onConfirmBaked {
            guard let rendered = ImageCropRenderer.render(
                sourceImage: sourceImage,
                preset: preset,
                aspectOption: aspectOption,
                transform: transform
            ) else { return }
            onConfirmBaked(rendered)
        }
    }
}

/// Create-flow preview that matches Feed/Profile rendering.
struct AdaptiveMediaPreviewImage: View {
    let image: UIImage
    let presentation: ContentImagePresentation

    @Environment(\.themeColors) private var colors

    var body: some View {
        let aspect = MediaImageOrientation.aspectRatio(of: image)

        AdaptiveInlineMediaContainer(
            imageAspect: aspect,
            feedPresentationForWidth: { _ in presentation },
            background: colors.fillSecondary
        ) { metrics in
            FeedMediaFramedImage(
                image: image,
                presentation: presentation,
                containerSize: CGSize(
                    width: metrics.containerWidth,
                    height: metrics.containerHeight
                )
            )
        }
        .allowsHitTesting(false)
    }
}
