import SwiftUI

/// Full-screen Instagram-style story editor — crop/zoom image + text overlays.
struct StoryEditorView: View {
    @State private var viewModel: StoryEditorViewModel
    @FocusState private var textFieldFocused: Bool

    private let onCancel: () -> Void
    private let onNext: (UIImage) -> Void

    @State private var imageDragStart: CGSize = .zero
    @State private var imagePinchStart: CGFloat?

    init(
        sourceImage: UIImage,
        onCancel: @escaping () -> Void,
        onNext: @escaping (UIImage) -> Void
    ) {
        _viewModel = State(initialValue: StoryEditorViewModel(sourceImage: sourceImage))
        self.onCancel = onCancel
        self.onNext = onNext
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
        }
        .accessibilityIdentifier("storyEditor.root")
    }

    private var topBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .foregroundStyle(.white)
                .accessibilityIdentifier("storyEditor.cancel")

            Spacer()

            Button {
                viewModel.beginAddingText()
                textFieldFocused = true
            } label: {
                Text("Aa")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("storyEditor.addText")
        }
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button("Next") {
                guard let rendered = viewModel.renderFinalImage() else { return }
                onNext(rendered)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, ExperienceSpacing.lg)
            .padding(.vertical, ExperienceSpacing.sm)
            .accessibilityIdentifier("storyEditor.next")
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
                        }
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
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
        let rect = StoryImageLayout.drawRect(
            imageSize: viewModel.sourceImage.size,
            canvasSize: canvasSize,
            scale: viewModel.canvas.imageScale,
            offset: viewModel.canvas.imageOffset
        )

        Image(uiImage: viewModel.sourceImage)
            .resizable()
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .gesture(imageDragGesture(canvasSize: canvasSize))
            .simultaneousGesture(imagePinchGesture(canvasSize: canvasSize))
            .allowsHitTesting(viewModel.canvas.selectedTextID == nil && !viewModel.isEditingText)
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
                                .stroke(Color.white, lineWidth: viewModel.selectedColor == color ? 2 : 0)
                        )
                        .onTapGesture { viewModel.setSelectedColor(color) }
                }
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
                .tint(.white)

                Button(role: .destructive) {
                    viewModel.deleteSelectedText()
                } label: {
                    Image(systemName: "trash")
                }
            }
            .foregroundStyle(.white)

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
            .foregroundStyle(.white)
            .padding(.bottom, ExperienceSpacing.md)
        }
        .padding(.top, ExperienceSpacing.sm)
        .background(Color.black.opacity(0.85))
    }

    private func alignmentButton(_ alignment: TextAlignment, symbol: String) -> some View {
        Button {
            viewModel.setSelectedAlignment(alignment)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(viewModel.selectedAlignment == alignment ? .bold : .regular))
        }
    }
}

private struct StoryTextOverlayView: View {
    let overlay: StoryTextOverlay
    let canvasSize: CGSize
    let isSelected: Bool
    let transformsEnabled: Bool
    let onSelect: () -> Void
    let onMove: (CGPoint) -> Void
    let onScale: (CGFloat) -> Void
    let onRotation: (CGFloat) -> Void
    let onEdit: () -> Void

    @State private var dragStartCenter: CGPoint?
    @State private var scaleStart: CGFloat?
    @State private var rotationStart: CGFloat?

    var body: some View {
        let center = CGPoint(
            x: overlay.normalizedCenter.x * canvasSize.width,
            y: overlay.normalizedCenter.y * canvasSize.height
        )

        Text(overlay.text.isEmpty ? " " : overlay.text)
            .font(.system(size: max(18, canvasSize.width * 0.065) * overlay.scale, weight: .semibold))
            .foregroundStyle(overlay.color.swiftUIColor)
            .multilineTextAlignment(overlay.alignment)
            .padding(overlay.showsBackground ? 8 : 0)
            .background {
                if overlay.showsBackground {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                }
            }
            .rotationEffect(.radians(Double(overlay.rotationRadians)))
            .position(center)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        .frame(width: 120, height: 44)
                        .position(center)
                }
            }
            .onTapGesture(count: 2, perform: onEdit)
            .onTapGesture(count: 1, perform: onSelect)
            .gesture(transformsEnabled ? dragGesture : nil)
            .simultaneousGesture(transformsEnabled ? pinchGesture : nil)
            .simultaneousGesture(transformsEnabled ? rotationGesture : nil)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                onSelect()
                if dragStartCenter == nil {
                    dragStartCenter = overlay.normalizedCenter
                }
                guard let start = dragStartCenter else { return }
                onMove(
                    CGPoint(
                        x: start.x + value.translation.width / canvasSize.width,
                        y: start.y + value.translation.height / canvasSize.height
                    )
                )
            }
            .onEnded { _ in
                dragStartCenter = nil
            }
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
