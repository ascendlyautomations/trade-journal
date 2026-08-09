import PhotosUI
import SwiftUI
import UIKit

/// Shared composer chrome for DM and Trade Room threads.
struct MessageComposerBar: View {
    @Binding var draft: String
    var isSending: Bool
    var placeholder: String = "Message"
    var showsTradeShare: Bool = true
    var onSend: () -> Void
    var onSendImage: (UIImage) -> Void
    var onSendTrade: (() -> Void)?

    @Environment(\.themeColors) private var colors
    @FocusState private var focused: Bool
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        HStack(alignment: .bottom, spacing: ExperienceSpacing.sm) {
            if showsTradeShare, let onSendTrade {
                Button(action: onSendTrade) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(colors.accent)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .disabled(isSending)
                .accessibilityLabel("Send trade")
                .accessibilityIdentifier("conversation.composer.trade")
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                ExperienceIcon(icon: .photo, size: .md, color: colors.accent)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Send photo")
            .accessibilityIdentifier("conversation.composer.photo")
            .disabled(isSending)

            TextField(placeholder, text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, ExperienceSpacing.xs + 2)
                .background(
                    colors.fillSecondary,
                    in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                )
                .focused($focused)
                .accessibilityIdentifier("conversation.composer.field")

            Button(action: onSend) {
                if isSending && draft.isEmpty {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? colors.accent : colors.tertiaryText)
                }
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("conversation.composer.send")
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .background(colors.navigationBackground.opacity(0.96))
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                await sendPickedPhoto(item)
                photoItem = nil
            }
        }
    }

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendPickedPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        onSendImage(image)
    }
}
