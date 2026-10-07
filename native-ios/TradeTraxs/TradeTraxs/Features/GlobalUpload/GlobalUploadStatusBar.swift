import SwiftUI

struct GlobalUploadStatusBar: View {
    @Bindable var coordinator: GlobalUploadCoordinator
    let presentation: GlobalUploadBarPresentation

    @Environment(\.themeEnvironment) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Button {
                coordinator.isQueuePresented = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(presentation.line)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 8)
                        if presentation.showsRetry, presentation.retryJobID == nil {
                            Text("Retry")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.colors.accent)
                        }
                    }
                    if let progress = presentation.progress, progress.isFinite {
                        ProgressView(value: min(1, max(0, progress)))
                            .tint(theme.colors.accent)
                    } else if !presentation.showsRetry {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if presentation.showsRetry, let retryJobID = presentation.retryJobID {
                Button("Retry") {
                    coordinator.retry(jobID: retryJobID)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
                .padding(.trailing, 16)
                .accessibilityIdentifier("globalUpload.statusBar.retry")
            }
        }
        .background(theme.colors.navigationBackground.opacity(0.98))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 0.5)
        }
        .accessibilityIdentifier("globalUpload.statusBar")
    }
}

struct GlobalUploadQueueSheet: View {
    @Bindable var coordinator: GlobalUploadCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeEnvironment) private var theme

    var body: some View {
        NavigationStack {
            List {
                ForEach(coordinator.jobs) { job in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(job.displayLine)
                            .font(.body.weight(.medium))
                        if let progress = job.progress, job.phase != .failed, progress.isFinite {
                            ProgressView(value: min(1, max(0, progress)))
                        }
                        if let error = job.errorMessage, job.phase == .failed {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                        if job.phase == .failed {
                            HStack {
                                Button("Retry") {
                                    coordinator.retry(jobID: job.id)
                                }
                                Button("Remove", role: .destructive) {
                                    coordinator.remove(jobID: job.id)
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Uploads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .experienceInsetGroupedListStyle(pageBackground: true)
        }
        .experienceSheetChrome()
    }
}

/// Upload queue sheet — attach once on ``MainTabShellView`` (not per tab stack).
struct GlobalUploadQueueSheetModifier: ViewModifier {
    @Bindable var coordinator: GlobalUploadCoordinator

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $coordinator.isQueuePresented) {
                GlobalUploadQueueSheet(coordinator: coordinator)
            }
    }
}

extension View {
    /// Lays out the upload banner in page content (above scroll areas / below navigation chrome).
    @MainActor
    func globalUploadPageLayout() -> some View {
        modifier(GlobalUploadPageLayoutModifier())
    }

    @MainActor
    func globalUploadQueueSheet() -> some View {
        globalUploadQueueSheet(coordinator: GlobalUploadCoordinator.shared)
    }

    @MainActor
    func globalUploadQueueSheet(coordinator: GlobalUploadCoordinator) -> some View {
        modifier(GlobalUploadQueueSheetModifier(coordinator: coordinator))
    }
}
