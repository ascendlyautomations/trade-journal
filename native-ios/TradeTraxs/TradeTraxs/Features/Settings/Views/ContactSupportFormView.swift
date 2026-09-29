import PhotosUI
import SwiftUI

struct ContactSupportFormView: View {
    let repository: any UserSubmissionRepository

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var topic: SupportContactTopic = .account
    @State private var message = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var screenshotPreview: UIImage?
    @State private var phase: UserSubmissionFormPhase = .editing

    var body: some View {
        Group {
            switch phase {
            case .succeeded:
                SubmissionSuccessPanel(
                    title: "Request submitted",
                    message: "Your support request was submitted. We will review it as soon as possible."
                ) {
                    dismiss()
                }
            default:
                formContent
            }
        }
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Help & Support")
        .scrollDismissesKeyboard(.interactively)
        .experienceKeyboardDismissOnTapOutside()
        .onChange(of: photoItem) { _, item in
            Task {
                screenshotPreview = await SubmissionPhotoLoading.loadUIImage(from: item)
            }
        }
        .accessibilityIdentifier("settings.support.contact")
    }

    private var formContent: some View {
        List {
            if case .failed(let error) = phase {
                Section {
                    SubmissionFailureBanner(message: error) {
                        phase = .editing
                    }
                }
            }

            Section {
                Picker("Subject", selection: $topic) {
                    ForEach(SupportContactTopic.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } header: {
                Text("Subject")
            }

            Section {
                TextField("Message", text: $message, axis: .vertical)
                    .lineLimit(5 ... 12)
            } footer: {
                Text("Describe what happened and what you need.")
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
                            Text("Submit")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit || phase == .submitting)
                .accessibilityIdentifier("settings.support.submit")
            }
        }
        .experienceInsetGroupedListStyle(pageBackground: true)
    }

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() async {
        guard canSubmit, phase != .submitting else { return }
        phase = .submitting
        do {
            try await repository.submitSupportTicket(
                SupportTicketSubmission(
                    category: topic.ticketCategory,
                    subject: topic.ticketSubject,
                    message: message,
                    screenshot: screenshotPreview
                )
            )
            phase = .succeeded
        } catch let error as UserSubmissionError {
            phase = .failed(error.displayMessage)
        } catch {
            phase = .failed("Couldn't submit your request. Please try again.")
        }
    }
}
