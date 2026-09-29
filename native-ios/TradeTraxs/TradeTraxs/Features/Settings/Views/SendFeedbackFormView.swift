import PhotosUI
import SwiftUI

struct SendFeedbackFormView: View {
    let repository: any UserSubmissionRepository

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackType: ProductFeedbackType = .featureRequest
    @State private var title = ""
    @State private var message = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var screenshotPreview: UIImage?
    @State private var phase: UserSubmissionFormPhase = .editing

    var body: some View {
        Group {
            switch phase {
            case .succeeded:
                SubmissionSuccessPanel(
                    title: "Feedback submitted",
                    message: "Thanks for helping shape TradeTraxs. We received your feedback."
                ) {
                    dismiss()
                }
            default:
                formContent
            }
        }
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Product Feedback")
        .scrollDismissesKeyboard(.interactively)
        .experienceKeyboardDismissOnTapOutside()
        .onChange(of: photoItem) { _, item in
            Task {
                screenshotPreview = await SubmissionPhotoLoading.loadUIImage(from: item)
            }
        }
        .accessibilityIdentifier("settings.productFeedback")
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
                Picker("Feedback type", selection: $feedbackType) {
                    ForEach(ProductFeedbackType.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } header: {
                Text("Type")
            }

            Section {
                TextField("Title (optional)", text: $title)
                TextField("Feedback", text: $message, axis: .vertical)
                    .lineLimit(5 ... 12)
            } footer: {
                Text("Tell us what you'd like to see or what could work better.")
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
                            Text("Submit Feedback")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit || phase == .submitting)
                .accessibilityIdentifier("settings.productFeedback.submit")
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
            try await repository.submitFeedback(
                FeedbackSubmission(
                    subject: feedbackType.composedSubject(optionalTitle: title),
                    message: message,
                    screenshot: screenshotPreview
                )
            )
            phase = .succeeded
        } catch let error as UserSubmissionError {
            phase = .failed(error.displayMessage)
        } catch {
            phase = .failed("Couldn't submit feedback. Please try again.")
        }
    }
}
