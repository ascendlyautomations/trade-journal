import SwiftUI

struct ContentReportSheet: View {
    @State private var viewModel: ContentReportSheetViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    var onDismiss: () -> Void
    var onBlockUser: ((ProfileID) -> Void)?

    init(
        request: ContentReportRequest,
        repository: any ContentReportRepository,
        onDismiss: @escaping () -> Void,
        onBlockUser: ((ProfileID) -> Void)? = nil
    ) {
        _viewModel = State(
            initialValue: ContentReportSheetViewModel(
                request: request,
                repository: repository
            )
        )
        self.onDismiss = onDismiss
        self.onBlockUser = onBlockUser
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .succeeded(let wasDuplicate):
                    successContent(wasDuplicate: wasDuplicate)
                case .failed(let message):
                    failureContent(message: message)
                default:
                    formContent
                }
            }
            .background(colors.groupedBackground.ignoresSafeArea())
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        close()
                    }
                    .disabled(viewModel.phase == .submitting)
                }
            }
        }
        .interactiveDismissDisabled(viewModel.phase == .submitting)
        .accessibilityIdentifier("contentReport.sheet")
    }

    private var formContent: some View {
        List {
            Section {
                Text("Reporting \(viewModel.request.subjectTitle)")
                    .experienceStyle(.body, color: colors.primaryText)
            } footer: {
                Text(
                    "Reports are reviewed under the TradeTraxs Community Guidelines."
                )
            }

            Section("Why are you reporting this?") {
                ForEach(ContentReportReason.allCases) { reason in
                    Button {
                        viewModel.selectReason(reason)
                    } label: {
                        HStack {
                            Text(reason.title)
                                .experienceStyle(.body, color: colors.primaryText)
                            Spacer()
                            if viewModel.selectedReason == reason {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(colors.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.showsDetailsField {
                Section("Additional details") {
                    TextField(
                        "Describe the issue…",
                        text: $viewModel.detailsText,
                        axis: .vertical
                    )
                    .lineLimit(3 ... 6)
                }
            }

            Section {
                Link("Community Guidelines", destination: communityGuidelinesURL)
            }

            Section {
                Button {
                    Task { await viewModel.submit() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.phase == .submitting {
                            ProgressView()
                        } else {
                            Text("Submit Report")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!viewModel.canSubmit || viewModel.phase == .submitting)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func successContent(wasDuplicate: Bool) -> some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(colors.success)
            Text(wasDuplicate ? "Already reported" : "Report submitted")
                .experienceStyle(.title3, color: colors.primaryText)
                .fontWeight(.semibold)
            Text(
                wasDuplicate
                    ? "You already reported this content. Our team will review it."
                    : "Thanks — our moderation team will review your report."
            )
            .experienceStyle(.body, color: colors.secondaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, ExperienceSpacing.lg)

            if let blockID = viewModel.request.blockUserOffer, let onBlockUser {
                Button("Block this user", role: .destructive) {
                    onBlockUser(blockID)
                    close()
                }
                .buttonStyle(.bordered)
            }

            Button("Done") {
                close()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(ExperienceSpacing.lg)
    }

    private func failureContent(message: String) -> some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(colors.warning)
            Text("Couldn't submit report")
                .experienceStyle(.title3, color: colors.primaryText)
                .fontWeight(.semibold)
            Text(message)
                .experienceStyle(.body, color: colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ExperienceSpacing.lg)
            Button("Try Again") {
                viewModel.retryAfterFailure()
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel") {
                close()
            }
            Spacer()
        }
        .padding(ExperienceSpacing.lg)
    }

    private var communityGuidelinesURL: URL {
        URL(string: "https://www.tradetraxs.com/community-guidelines")!
    }

    private func close() {
        onDismiss()
        dismiss()
    }
}
