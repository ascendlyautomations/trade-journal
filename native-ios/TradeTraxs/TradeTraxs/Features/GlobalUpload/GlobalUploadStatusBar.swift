import SwiftUI

struct GlobalUploadStatusBar: View {
    @Bindable var coordinator: GlobalUploadCoordinator
    let presentation: GlobalUploadBarPresentation

    @Environment(\.themeEnvironment) private var theme

    var body: some View {
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
                    if presentation.showsRetry {
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
            .background(theme.colors.navigationBackground.opacity(0.98))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.colors.border)
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
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
        }
    }
}

struct GlobalUploadChromeModifier: ViewModifier {
    @Bindable var coordinator: GlobalUploadCoordinator

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let presentation = coordinator.barPresentation {
                    GlobalUploadStatusBar(
                        coordinator: coordinator,
                        presentation: presentation
                    )
                }
            }
            .sheet(isPresented: $coordinator.isQueuePresented) {
                GlobalUploadQueueSheet(coordinator: coordinator)
            }
    }
}

extension View {
    func globalUploadChrome(coordinator: GlobalUploadCoordinator = .shared) -> some View {
        modifier(GlobalUploadChromeModifier(coordinator: coordinator))
    }
}
