import PhotosUI
import SwiftUI
import UIKit

/// Shared composer chrome for DM and Trade Room threads.
struct MessageComposerBar: View {
    @Binding var draft: String
    var isSending: Bool
    var isEnabled: Bool = true
    var placeholder: String = "Message"
    var showsTradeShare: Bool = true
    var onSend: () -> Void
    var onSendImage: (UIImage) -> Void
    var onSendVoice: ((URL, TimeInterval) -> Void)?
    var onSendTrade: (() -> Void)?

    @Environment(\.themeColors) private var colors
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var showsPhotoPicker = false
    @State private var keyboardSendScheduled = false
    @State private var showsMicrophoneSettings = false
    @StateObject private var voiceRecorder = VoiceMessageRecorder()

    var body: some View {
        Group {
            if voiceRecorder.phase == .recording {
                recordingBar
            } else {
                composerBar
            }
        }
        .padding(.horizontal, ExperienceSpacing.xs)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.navigationBackground.opacity(0.96))
        .photosPicker(
            isPresented: $showsPhotoPicker,
            selection: $photoItem,
            matching: MediaPickerPolicy.imageOnly.matching
        )
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                voiceRecorder.handleEnteredBackground()
            }
        }
        .alert("Microphone access is off", isPresented: $showsMicrophoneSettings) {
            Button("Not Now", role: .cancel) {}
            Button("Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        } message: {
            Text("Turn on microphone access in Settings to send voice messages.")
        }
        .experienceFormFocusSync($focused)
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: ExperienceSpacing.xxs) {
            attachmentLauncher

            messageField

            if canSendText, isEnabled {
                sendButton
            }
        }
    }

    /// Compact launcher for the existing photo picker and Send Trade flows.
    private var attachmentLauncher: some View {
        Menu {
            Button {
                presentPhotoPicker()
            } label: {
                Label("Photo", systemImage: "photo")
            }
            .accessibilityLabel("Send photo")
            .accessibilityIdentifier("conversation.composer.photo")

            if showsTradeShare, let onSendTrade {
                Button(action: onSendTrade) {
                    Label("Send Trade", systemImage: "chart.line.uptrend.xyaxis")
                }
                .accessibilityLabel("Send trade")
                .accessibilityIdentifier("conversation.composer.trade")
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
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: true)
        .disabled(isSending || !isEnabled)
        .accessibilityLabel("Add")
        .accessibilityIdentifier("conversation.composer.add")
    }

    private var messageField: some View {
        HStack(alignment: .center, spacing: 0) {
            // Vertical TextField must never be measured at an infinite/NaN width.
            // The first character removes the mic and inserts Send, and that pass
            // was proposing a non-finite width into UITextView.
            ComposerFiniteWidthLayout {
                TextField(placeholder, text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .fixedSize(horizontal: false, vertical: true)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .focused($focused)
                    .submitLabel(.send)
                    .disabled(!isEnabled)
                    .onSubmit(submitFromKeyboard)
                    .onChange(of: draft) { previous, updated in
                        guard ComposerKeyboardSubmit.insertedReturn(from: previous, to: updated) else { return }
                        draft = previous
                        submitFromKeyboard()
                    }
                    .accessibilityIdentifier("conversation.composer.field")
                    .experienceTextInputProbe(
                        screen: "conversation",
                        field: "conversation.composer.field",
                        text: draft,
                        isFocused: focused
                    )
            }
            .layoutPriority(1)

            if showsInlineMicrophone {
                microphoneButton
                    .padding(.trailing, ExperienceSpacing.xxs)
            }
        }
        .padding(.leading, ExperienceSpacing.sm)
        .padding(.trailing, showsInlineMicrophone ? 0 : ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .frame(
            minWidth: ExperienceAccessibility.minTouchTarget,
            maxWidth: .infinity,
            minHeight: ExperienceAccessibility.minTouchTarget,
            alignment: .leading
        )
        .background(
            colors.fillSecondary,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
        )
    }

    private var microphoneButton: some View {
        Button {
            Task {
                let result = await voiceRecorder.start()
                if result.showSettings {
                    showsMicrophoneSettings = true
                }
            }
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(colors.secondaryText)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSending || !isEnabled)
        .accessibilityLabel("Record voice message")
        .accessibilityIdentifier("conversation.composer.mic")
    }

    private var sendButton: some View {
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
        .fixedSize(horizontal: true, vertical: true)
        .disabled(isSending)
        .accessibilityLabel("Send")
        .accessibilityIdentifier("conversation.composer.send")
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

    /// Mic stays inside the field until Send takes over for non-empty text.
    private var showsInlineMicrophone: Bool {
        onSendVoice != nil && !(canSendText && isEnabled)
    }

    /// Menu dismissal and the photo picker cannot present in the same turn.
    private func presentPhotoPicker() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            showsPhotoPicker = true
        }
    }

    /// Vertical `TextField` reports the Send key as an inserted newline and may also call submit.
    /// Both routes use the same `onSend` closure as the on-screen button, once per key press.
    private func submitFromKeyboard() {
        guard !keyboardSendScheduled else { return }
        guard canSendText, isEnabled, !isSending else { return }
        keyboardSendScheduled = true
        onSend()
        Task { @MainActor in
            keyboardSendScheduled = false
        }
    }

    private func sendPickedPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        onSendImage(image)
    }
}

/// Keeps non-finite widths out of the vertical message field.
enum ComposerTextLayoutClamp {
    static let minimumProposalWidth: CGFloat = 1

    static func finiteProposalWidth(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite, proposed > 0 else { return minimumProposalWidth }
        return proposed
    }

    static func finiteDimension(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        guard value.isFinite, value >= 0 else { return fallback }
        return value
    }

    static func finiteCoordinate(_ value: CGFloat) -> CGFloat {
        value.isFinite ? value : 0
    }
}

/// Proposes only a finite width to the composer text field.
private struct ComposerFiniteWidthLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let proposedWidth = proposal.width, proposedWidth.isFinite, proposedWidth > 0 else {
            // Unspecified or non-finite: do not ask UITextView to lay out.
            return CGSize(width: ComposerTextLayoutClamp.minimumProposalWidth, height: 22)
        }
        guard let subview = subviews.first else {
            return CGSize(width: proposedWidth, height: 0)
        }
        let measured = subview.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
        let height = measured.height.isFinite && measured.height > 0 ? measured.height : 22
        return CGSize(width: proposedWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let width = ComposerTextLayoutClamp.finiteDimension(bounds.width, fallback: ComposerTextLayoutClamp.minimumProposalWidth)
        let height = ComposerTextLayoutClamp.finiteDimension(bounds.height, fallback: 0)
        let x = ComposerTextLayoutClamp.finiteCoordinate(bounds.minX)
        let y = ComposerTextLayoutClamp.finiteCoordinate(bounds.minY)
        subview.place(
            at: CGPoint(x: x, y: y),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: max(width, ComposerTextLayoutClamp.minimumProposalWidth), height: height > 0 ? height : nil)
        )
    }
}

enum ComposerKeyboardSubmit {
    /// True when `updated` is `previous` plus one newline. Pasted multiline text is not a submit.
    static func insertedReturn(from previous: String, to updated: String) -> Bool {
        guard updated.count == previous.count + 1 else { return false }
        var previousIndex = previous.startIndex
        var updatedIndex = updated.startIndex
        while previousIndex < previous.endIndex,
              updatedIndex < updated.endIndex,
              previous[previousIndex] == updated[updatedIndex] {
            previous.formIndex(after: &previousIndex)
            updated.formIndex(after: &updatedIndex)
        }
        guard updatedIndex < updated.endIndex, updated[updatedIndex] == "\n" else { return false }
        updated.formIndex(after: &updatedIndex)
        return previous[previousIndex...] == updated[updatedIndex...]
    }
}
