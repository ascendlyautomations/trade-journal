import SwiftUI

/// Shared screenshot preview for Admin submission queues (Support, Bug Reports, …).
struct AdminSubmissionScreenshotSection: View {
    let screenshotURL: String?

    @State private var showsFullScreen = false
    @Environment(\.themeColors) private var colors

    var body: some View {
        Section("Screenshot") {
            if let urlString = screenshotURL?.trimmingCharacters(in: .whitespacesAndNewlines),
               !urlString.isEmpty,
               let url = URL(string: urlString) {
                Button {
                    showsFullScreen = true
                } label: {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .frame(height: 160)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md))
                        case .failure:
                            Text("Couldn't load screenshot")
                                .experienceStyle(.footnote, color: colors.loss)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View screenshot")
            } else {
                Text("No screenshot attached")
                    .experienceStyle(.footnote, color: colors.tertiaryText)
            }
        }
        .fullScreenCover(isPresented: $showsFullScreen) {
            if let urlString = screenshotURL, let url = URL(string: urlString) {
                AdminSubmissionScreenshotFullScreenView(url: url) {
                    showsFullScreen = false
                }
            }
        }
    }
}

private struct AdminSubmissionScreenshotFullScreenView: View {
    let url: URL
    let onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .success(let image):
                    ScrollView {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                case .failure:
                    ExperienceErrorState(
                        title: "Couldn't load screenshot",
                        message: "The image may have been removed.",
                        onRetry: nil
                    )
                @unknown default:
                    EmptyView()
                }
            }
            .background(colors.backgroundPrimary)
            .adminExperienceChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onClose() }
                }
            }
        }
    }
}
