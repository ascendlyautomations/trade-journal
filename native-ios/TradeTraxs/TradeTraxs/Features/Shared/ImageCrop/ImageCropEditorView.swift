import SwiftUI
import UIKit

/// Shared pinch/drag crop editor — WYSIWYG aspect-fill viewport; preview and export share one transform.
struct ImageCropEditorView: View {
    let sourceImage: UIImage
    let preset: ImageCropEditorPreset
    let onCancel: () -> Void
    var onConfirmFeed: ((ImageCropSelectionResult) -> Void)?
    var onConfirmBaked: ((UIImage) -> Void)?

    @Environment(\.themeColors) private var colors
    @State private var aspectOption: ImageCropAspectOption
    @State private var transform = ImageCropTransform.default
    @State private var activeViewportSize: CGSize = .zero
    @State private var panSessionStartTranslation: CGSize = .zero
    @State private var pinchSessionStartZoom: CGFloat = 1
    @State private var pinchSessionStartTranslation: CGSize = .zero
    @State private var isPinchActive = false
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

    /// Aspect-fill pan/pinch for the selected 1:1, 4:5, or 16:9 frame.
    private var usesInteractiveCrop: Bool {
        FeedMediaLayout.requiresFillCrop(
            imageAspect: imageAspect,
            aspectOption: aspectOption
        )
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

                if usesInteractiveCrop {
                    Text("This is how your image will appear in the Feed.")
                        .experienceStyle(.caption, color: colors.secondaryText)
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
                    Button("Choose Photo") {
                        Task { await confirmCrop() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(true)
        .accessibilityIdentifier("imageCrop.editor")
    }

    private var aspectPicker: some View {
        HStack(spacing: 2) {
            ForEach(preset.allowedAspectOptions) { option in
                Button {
                    guard aspectOption != option else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        aspectOption = option
                        resetTransform()
                    }
                } label: {
                    Text(option.segmentTitle)
                        .font(.caption.weight(aspectOption == option ? .semibold : .regular))
                        .foregroundStyle(aspectOption == option ? colors.primaryText : colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if aspectOption == option {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(colors.backgroundPrimary)
                                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(aspectOption == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background(colors.fillSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityIdentifier("imageCrop.aspectPicker")
    }

    private var cropViewport: some View {
        GeometryReader { proxy in
            let frameSize = FeedMediaLayout.editorViewportSize(
                containerWidth: proxy.size.width,
                imagePixelSize: imagePixelSize,
                aspectOption: aspectOption
            )

            cropViewportContent(frameSize: frameSize)
                .preference(key: CropViewportSizePreferenceKey.self, value: frameSize)
        }
        .frame(maxWidth: .infinity)
        .frame(height: editorViewportHeightEstimate(forWidth: max(UIScreen.main.bounds.width - 32, 1)))
        .onPreferenceChange(CropViewportSizePreferenceKey.self) { size in
            if size.width > 0, size.height > 0 {
                activeViewportSize = size
            }
        }
    }

    private func editorViewportHeightEstimate(forWidth width: CGFloat) -> CGFloat {
        if activeViewportSize.height > 0 {
            return activeViewportSize.height
        }
        return FeedMediaLayout.editorViewportSize(
            containerWidth: width,
            imagePixelSize: imagePixelSize,
            aspectOption: aspectOption
        ).height
    }

    @ViewBuilder
    private func cropViewportContent(frameSize: CGSize) -> some View {
        let width = frameSize.width
        let height = frameSize.height

        ZStack(alignment: .topLeading) {
            colors.fillSecondary

            if usesInteractiveCrop {
                let geometry = cropGeometry(viewportSize: frameSize)
                CropEditorImagePreview(image: sourceImage, geometry: geometry)
                    .frame(width: width, height: height)

                cropMask(width: width, height: height)

                ImageCropViewportInteraction(
                    onPanBegan: {
                        panSessionStartTranslation = transform.offset
                    },
                    onPan: { delta in
                        let proposed = CGSize(
                            width: panSessionStartTranslation.width + delta.width,
                            height: panSessionStartTranslation.height + delta.height
                        )
                        commitTransform(
                            userScale: transform.zoom,
                            translation: proposed,
                            viewportSize: frameSize
                        )
                    },
                    onPanEnded: {
                        panSessionStartTranslation = transform.offset
                    },
                    onPinchBegan: { _ in
                        isPinchActive = true
                        pinchSessionStartZoom = transform.zoom
                        pinchSessionStartTranslation = transform.offset
                    },
                    onPinch: { magnification, anchor in
                        transform = ImageCropViewportMath.zoomAroundAnchor(
                            anchor: anchor,
                            imagePixelSize: imagePixelSize,
                            viewportSize: frameSize,
                            startUserScale: pinchSessionStartZoom,
                            startTranslation: pinchSessionStartTranslation,
                            magnification: magnification,
                            maxUserScale: preset.maxZoom
                        )
                        #if DEBUG
                        CropTransformProbe.log(
                            layout: cropGeometry(viewportSize: frameSize).layout,
                            viewport: frameSize,
                            pinchAnchor: anchor
                        )
                        #endif
                    },
                    onPinchEnded: {
                        isPinchActive = false
                        panSessionStartTranslation = transform.offset
                        pinchSessionStartZoom = transform.zoom
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(uiImage: sourceImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width, height: height)

                cropMask(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .stroke(colors.accent.opacity(0.85), lineWidth: 1.5)
        }
        .contentShape(Rectangle())
    }

    private func cropGeometry(viewportSize: CGSize) -> CropViewportGeometry {
        CropViewportGeometry(
            sourcePixelSize: imagePixelSize,
            viewportSize: viewportSize,
            userScale: transform.zoom,
            translation: transform.offset,
            maxUserScale: preset.maxZoom
        )
    }

    private func commitTransform(
        userScale: CGFloat,
        translation: CGSize,
        viewportSize: CGSize
    ) {
        transform = ImageCropViewportMath.clampedTransform(
            imagePixelSize: imagePixelSize,
            viewportSize: viewportSize,
            userScale: userScale,
            translation: translation,
            maxUserScale: preset.maxZoom
        )
    }

    private func resetTransform() {
        transform = .default
        panSessionStartTranslation = .zero
        pinchSessionStartZoom = 1
        pinchSessionStartTranslation = .zero
        isPinchActive = false
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

        let viewport = resolvedViewportSize()
        let geometry = cropGeometry(viewportSize: viewport)

        #if DEBUG
        CropGeometryProbe.logPreview(geometry)
        #endif

        if let onConfirmFeed {
            guard let exported = ImageCropRenderer.exportFeedCrop(
                sourceImage: sourceImage,
                aspectOption: aspectOption,
                geometry: geometry
            ) else { return }
            onConfirmFeed(
                ImageCropSelectionResult(
                    image: exported,
                    aspectMode: aspectOption,
                    sourcePixelSize: imagePixelSize
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

    private func resolvedViewportSize() -> CGSize {
        if activeViewportSize.width > 0, activeViewportSize.height > 0 {
            return activeViewportSize
        }
        let width = max(UIScreen.main.bounds.width - 32, 1)
        return FeedMediaLayout.editorViewportSize(
            containerWidth: width,
            imagePixelSize: imagePixelSize,
            aspectOption: aspectOption
        )
    }
}

/// Create-flow preview — displays the physically cropped UIImage only.
struct AdaptiveMediaPreviewImage: View {
    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isImage)
    }
}
