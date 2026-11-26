import SwiftUI

struct CommentComposerView: View {
    @Bindable var viewModel: CommentsViewModel
    var imagePipeline: (any ImagePipeline)?

    @Environment(\.themeColors) private var colors
    @FocusState private var focused: Bool
    /// Vertical `TextField` can report Return as both a newline and `onSubmit`.
    @State private var keyboardSendScheduled = false
    @State private var pendingPrivateTradeConfirm: Trade?

    private var canPost: Bool {
        let text = viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty || viewModel.pendingSharedTrade != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            if let replyTarget = viewModel.replyTarget {
                replyBanner(for: replyTarget)
            }

            if let trade = viewModel.pendingSharedTrade, let imagePipeline {
                pendingTradePreview(trade: trade, imagePipeline: imagePipeline)
                if trade.visibility == .private {
                    Text(CommentTradeShareSupport.privateAttachmentDisclaimer)
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .padding(.horizontal, ExperienceSpacing.xs)
                }
            }

            HStack(alignment: .bottom, spacing: ExperienceSpacing.sm) {
                attachmentLauncher

                TextField(
                    viewModel.replyTarget == nil ? "Add a comment…" : "Add to reply…",
                    text: $viewModel.draft,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, ExperienceSpacing.xs)
                .background(colors.fillPrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(submitFromKeyboard)
                .onChange(of: viewModel.draft) { previous, updated in
                    guard ComposerKeyboardSubmit.insertedReturn(from: previous, to: updated) else { return }
                    viewModel.draft = previous
                    submitFromKeyboard()
                }
                .onChange(of: focused) { _, isFocused in
                    viewModel.maintainKeyboardScrollAnchor = isFocused
                }
                .experienceKeyboardExcludesDoneToolbarWhenFocused(focused)
                .accessibilityIdentifier("interaction.comment.composer")
                .experienceTextInputProbe(
                    screen: "comments",
                    field: "interaction.comment.composer",
                    text: viewModel.draft,
                    isFocused: focused
                )

                Button {
                    Task { await viewModel.submit() }
                } label: {
                    Group {
                        if viewModel.isPosting {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(
                                    canPost ? colors.accent : colors.tertiaryText
                                )
                        }
                    }
                    .experienceTouchTarget()
                }
                .buttonStyle(.experiencePlain)
                .disabled(viewModel.isPosting || !canPost)
                .accessibilityLabel("Post comment")
                .accessibilityIdentifier("interaction.comment.send")
            }
        }
        .onChange(of: viewModel.composerFocusToken) { _, _ in
            focused = true
            viewModel.maintainKeyboardScrollAnchor = true
        }
        .experienceFormFocusSync($focused)
        .alert(
            "Attach private trade?",
            isPresented: Binding(
                get: { pendingPrivateTradeConfirm != nil },
                set: { if !$0 { pendingPrivateTradeConfirm = nil } }
            )
        ) {
            Button("Attach", role: .none) {
                if let trade = pendingPrivateTradeConfirm {
                    viewModel.stageSharedTrade(trade)
                }
                pendingPrivateTradeConfirm = nil
            }
            Button("Cancel", role: .cancel) {
                pendingPrivateTradeConfirm = nil
            }
        } message: {
            Text(CommentTradeShareSupport.privateAttachmentDisclaimer)
        }
        .sheet(isPresented: $viewModel.showsTradePicker) {
            if let imagePipeline {
                TradeSharePickerSheet(
                    trades: viewModel.tradePickerTrades,
                    imagePipeline: imagePipeline,
                    isLoading: viewModel.isLoadingTradePicker,
                    title: "Attach Trade",
                    onSelect: { trade in
                        if trade.visibility == .private {
                            pendingPrivateTradeConfirm = trade
                        } else {
                            viewModel.stageSharedTrade(trade)
                        }
                    },
                    onClose: {
                        viewModel.showsTradePicker = false
                    }
                )
                .task {
                    await viewModel.loadTradePickerIfNeeded()
                }
            }
        }
    }

    private var attachmentLauncher: some View {
        Menu {
            Button {
                viewModel.presentTradePicker()
            } label: {
                Label("Trade", systemImage: "chart.line.uptrend.xyaxis")
            }
            .accessibilityIdentifier("interaction.comment.attach.trade")
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
        .disabled(viewModel.isPosting)
        .accessibilityLabel("Add attachment")
        .accessibilityIdentifier("interaction.comment.attach")
    }

    @ViewBuilder
    private func pendingTradePreview(trade: Trade, imagePipeline: any ImagePipeline) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.xs) {
            SharedTradePreviewCard(
                trade: trade,
                tradeID: trade.id,
                imagePipeline: imagePipeline,
                style: .composerStrip
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                viewModel.clearPendingSharedTrade()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(colors.tertiaryText)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Remove attached trade")
        }
    }

    /// Return and the send button both call ``CommentsViewModel/submit()``.
    /// One key press must not run it twice.
    private func submitFromKeyboard() {
        guard !keyboardSendScheduled else { return }
        guard canPost, !viewModel.isPosting else { return }
        keyboardSendScheduled = true
        Task { @MainActor in
            await viewModel.submit()
            keyboardSendScheduled = false
        }
    }

    @ViewBuilder
    private func replyBanner(for replyTarget: CommentThreadSupport.ReplyTarget) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to @\(replyTarget.mentionUsername)")
                    .experienceStyle(.caption, color: colors.accent)
                if !replyTarget.preview.isEmpty {
                    Text("“\(replyTarget.preview)”")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                viewModel.cancelReply()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.tertiaryText)
                    .frame(width: 28, height: 28)
                    .background(colors.fillPrimary, in: Circle())
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Cancel reply")
            .accessibilityIdentifier("interaction.comment.replyCancel")
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.fillPrimary.opacity(0.6), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(colors.accent)
                .frame(width: 3)
        }
    }
}