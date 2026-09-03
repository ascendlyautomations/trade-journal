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
    var onSendVoice: ((URL, TimeInterval) -> Void)?
    var onSendTrade: (() -> Void)?

    @Environment(\.themeColors) private var colors
    @FocusState private var focused: Bool
    @State private var photoItem: PhotosPickerItem?
    @StateObject private var voiceRecorder = VoiceMessageRecorder()

    var body: some View {
        Group {
            if voiceRecorder.phase == .recording {
                recordingBar
            } else {
                composerBar
            }
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
        .onChange(of: voiceRecorder.completedRecording?.url) { _, _ in
            guard let completed = voiceRecorder.completedRecording else { return }
            onSendVoice?(completed.url, completed.duration)
        }
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: ExperienceSpacing.sm) {
            if showsTradeShare, let onSendTrade {
                Button(action: onSendTrade) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(colors.accent)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .experienceTouchTarget()
                .disabled(isSending)
                .accessibilityLabel("Send trade")
                .accessibilityIdentifier("conversation.composer.trade")
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                ExperienceIcon(icon: .photo, size: .md, color: colors.accent)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .experienceTouchTarget()
            .accessibilityLabel("Send photo")
            .accessibilityIdentifier("conversation.composer.photo")
            .disabled(isSending)

            TextField(placeholder, text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, ExperienceSpacing.xs + 2)
                .background(
                    colors.fillSecondary,
                    in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                )
                .focused($focused)
                .submitLabel(.send)
                .onSubmit {
                    guard canSendText else { return }
                    onSend()
                }
                .accessibilityIdentifier("conversation.composer.field")

            if canSendText {
                Button(action: onSend) {
                    if isSending {
                        ProgressView()
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(colors.accent)
                    }
                }
                .experienceTouchTarget()
                .disabled(isSending)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("conversation.composer.send")
            } else if onSendVoice != nil {
                Button {
                    Task { _ = await voiceRecorder.start() }
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(colors.accent)
                        .frame(width: 36, height: 36)
                }
                .experienceTouchTarget()
                .disabled(isSending)
                .accessibilityLabel("Record voice message")
                .accessibilityIdentifier("conversation.composer.mic")
            }
        }
    }

    private var recordingBar: some View {
        HStack(spacing: ExperienceSpacing.md) {
            Button {
                voiceRecorder.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colors.secondaryText)
                    .frame(width: 36, height: 36)
            }
            .experienceTouchTarget()
            .accessibilityLabel("Cancel recording")

            HStack(spacing: ExperienceSpacing.xs) {
                Circle()
                    .fill(colors.error)
                    .frame(width: 8, height: 8)
                Text(VoiceMessageSupport.formatDuration(voiceRecorder.elapsed))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(colors.primaryText)
            }
            .frame(maxWidth: .infinity)

            Button {
                guard let result = voiceRecorder.finish() else { return }
                onSendVoice?(result.url, result.duration)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(colors.accent)
            }
            .experienceTouchTarget()
            .accessibilityLabel("Send voice message")
            .accessibilityIdentifier("conversation.composer.voice.send")
        }
    }

    private var canSendText: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendPickedPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        onSendImage(image)
    }
}
