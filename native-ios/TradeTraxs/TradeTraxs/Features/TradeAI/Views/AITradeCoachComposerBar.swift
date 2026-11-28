import PhotosUI
import SwiftUI

/// DM-style composer for Trade AI threads: + launcher, optional trade staging, image preview.
struct AITradeCoachComposerBar: View {
    @Binding var draft: String
    var isLoading: Bool
    var showsTradeAttach: Bool
    var stagedTrade: Trade?
    var pendingImageData: Data?
    var imagePipeline: (any ImagePipeline)?
    var onSend: () -> Void
    var onRemoveTrade: () -> Void
    var onRemoveImage: () -> Void
    var onAttachTrade: () -> Void
    var onPickedImage: (Data) -> Void

    @Environment(\.themeColors) private var colors
    @FocusState private var composerFocused: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var showsPhotoPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            if let stagedTrade, let imagePipeline {
                MessageComposerTradeStagingRow(
                    trade: stagedTrade,
                    imagePipeline: imagePipeline,
                    onRemove: onRemoveTrade
                )
            }

            if let data = pendingImageData, let image = UIImage(data: data) {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm))
                    Button("Remove", action: onRemoveImage)
                        .font(.system(.caption, design: .default).weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, ExperienceSpacing.md)
            }

            HStack(alignment: .center, spacing: ExperienceSpacing.xxs) {
                attachmentLauncher

                TextField("Ask a follow-up…", text: $draft, axis: .vertical)
                    .lineLimit(1 ... 5)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .frame(minHeight: ExperienceAccessibility.minTouchTarget, alignment: .center)
                    .background(colors.fillSecondary, in: RoundedRectangle(cornerRadius: ExperienceRadius.md))
                    .focused($composerFocused)

                sendButton
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.vertical, ExperienceSpacing.xs)
            .background(colors.navigationBackground.opacity(0.96))
        }
        .experienceFormFocusSync($composerFocused)
        .photosPicker(
            isPresented: $showsPhotoPicker,
            selection: $photoItem,
            matching: MediaPickerPolicy.imageOnly.matching
        )
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    onPickedImage(data)
                }
                photoItem = nil
            }
        }
    }

    private var attachmentLauncher: some View {
        Menu {
            Button {
                showsPhotoPicker = true
            } label: {
                Label("Photo", systemImage: "photo")
            }
            if showsTradeAttach {
                Button(action: onAttachTrade) {
                    Label("Attach Trade", systemImage: "chart.line.uptrend.xyaxis")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.accent)
                .frame(width: 28, height: 28)
                .background(colors.fillSecondary, in: Circle())
                .frame(
                    width: ExperienceAccessibility.minTouchTarget,
                    height: ExperienceAccessibility.minTouchTarget
                )
                .contentShape(Rectangle())
                .experienceControlHitTarget()
        }
        .menuStyle(.button)
        .buttonStyle(.experiencePlain)
        .fixedSize(horizontal: true, vertical: true)
        .disabled(isLoading)
        .accessibilityLabel("Add")
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: isLoading ? "hourglass" : "arrow.up.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(canSend ? colors.accent : colors.tertiaryText)
                .frame(width: 28, height: 28)
                .frame(
                    width: ExperienceAccessibility.minTouchTarget,
                    height: ExperienceAccessibility.minTouchTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.experiencePlain)
        .fixedSize(horizontal: true, vertical: true)
        .disabled(!canSend)
        .accessibilityLabel("Send")
    }

    private var canSend: Bool {
        !isLoading && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}