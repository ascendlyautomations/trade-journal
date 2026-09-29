import PhotosUI
import SwiftUI

struct ReportBugFormView: View {
    let repository: any UserSubmissionRepository

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var severity: BugReportSeverity = .medium
    @State private var photoItem: PhotosPickerItem?
    @State private var screenshotPreview: UIImage?
    @State private var phase: UserSubmissionFormPhase = .editing

    var body: some View {
        Group {
            switch phase {
            case .succeeded:
                SubmissionSuccessPanel(
                    title: "Report submitted",
                    message: "Thanks. Your report was submitted."
                ) {
                    dismiss()
                }
            default:
                formContent
            }
        }
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Report a Bug")
        .onChange(of: photoItem) { _, item in
            Task {
                screenshotPreview = await SubmissionPhotoLoading.loadUIImage(from: item)
            }
        }
        .accessibilityIdentifier("settings.support.bug")
    }

    private var formContent: some View {
        List {
            if case .failed(let error) = phase {
                Section {
                    SubmissionFailureBanner(message: error)
                }
            }

            Section {
                TextField("Title", text: $title)
                    .onChange(of: title) { _, newValue in
                        if newValue.count > 200 {
                            title = String(newValue.prefix(200))
                        }
                    }
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(5 ... 10)
                Picker("Severity", selection: $severity) {
                    ForEach(BugReportSeverity.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
            } footer: {
                Text("App version and device details are included automatically.")
                    .foregroundStyle(colors.tertiaryText)
            }

            SubmissionScreenshotSection(
                photoItem: $photoItem,
                previewImage: $screenshotPreview
            )

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if phase == .submitting {
                            ProgressView()
                        } else {
                            Text("Submit report")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit || phase == .submitting)
            }
        }
        .experienceInsetGroupedListStyle(pageBackground: true)
    }

    private var canSubmit: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedTitle.isEmpty && !trimmedDescription.isEmpty && trimmedTitle.count <= 200
    }

    private func submit() async {
        guard canSubmit, phase != .submitting else { return }
        phase = .submitting
        do {
            try await repository.submitBugReport(
                BugReportSubmission(
                    title: title,
                    description: description,
                    severity: severity,
                    screenshot: screenshotPreview
                )
            )
            phase = .succeeded
        } catch let error as UserSubmissionError {
            phase = .failed(error.displayMessage)
        } catch {
            phase = .failed("Couldn't submit your report. Please try again.")
        }
    }
}
