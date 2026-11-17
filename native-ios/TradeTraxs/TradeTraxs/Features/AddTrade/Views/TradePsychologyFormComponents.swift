import SwiftUI

/// Shared conviction, emotion, execution, and notes UI for Add Trade psychology and Quick Reflection.
enum TradePsychologyFormComponents {
    static let sectionSpacing = ExperienceSpacing.xxs / 2

    static func convictionSelector(confidenceLevel: Binding<Int>, colors: SemanticColorPalette) -> some View {
        HStack(spacing: ExperienceSpacing.xs) {
            ForEach(1...5, id: \.self) { level in
                Button {
                    if confidenceLevel.wrappedValue == level {
                        confidenceLevel.wrappedValue = 0
                    } else {
                        confidenceLevel.wrappedValue = level
                    }
                } label: {
                    Text("\(level)")
                        .font(ExperienceTypography.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ExperienceSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                .fill(
                                    confidenceLevel.wrappedValue == level
                                        ? colors.accent.opacity(0.18)
                                        : colors.fillSecondary
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                .strokeBorder(
                                    confidenceLevel.wrappedValue == level
                                        ? colors.accent
                                        : colors.separator,
                                    lineWidth: confidenceLevel.wrappedValue == level ? 1.5 : 1
                                )
                        )
                        .foregroundStyle(
                            confidenceLevel.wrappedValue == level
                                ? colors.accent
                                : colors.primaryText
                        )
                }
                .buttonStyle(.experiencePlain)
                .accessibilityLabel("Conviction \(level) of 5")
                .accessibilityAddTraits(confidenceLevel.wrappedValue == level ? .isSelected : [])
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    static func emotionPickerSection(
        header: String,
        pickerLabel: String,
        selection: Binding<String>,
        customText: Binding<String>,
        accessibilityPrefix: String
    ) -> some View {
        Section(header) {
            Picker(pickerLabel, selection: selection) {
                Text("Not set").tag("")
                ForEach(TradeReviewCatalog.emotionOptions, id: \.self) { emotion in
                    Text(emotion).tag(emotion)
                }
            }
            .accessibilityIdentifier("\(accessibilityPrefix).emotion")

            if selection.wrappedValue == TradeReviewCatalog.customPsychologyToken {
                TextField("Custom emotion", text: customText)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("\(accessibilityPrefix).emotion.custom")
            }
        }
    }

    static func executionRatingSection(
        rating: Binding<Int>,
        accessibilityIdentifier: String
    ) -> some View {
        Section("Execution") {
            CompactRatingSelector(title: "Execution rating", value: rating)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    static func psychologyNotesSection(
        text: Binding<String>,
        colors: SemanticColorPalette,
        accessibilityIdentifier: String,
        textInputScreen: String = "quickReflection"
    ) -> some View {
        Section("Psychology notes") {
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Thought process before, during, and after…")
                        .experienceStyle(.body, color: colors.tertiaryText)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(ExperienceTypography.body)
                    .foregroundStyle(colors.primaryText)
                    .frame(minHeight: 96, alignment: .top)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .experienceTextInputProbe(
                        screen: textInputScreen,
                        field: accessibilityIdentifier,
                        text: text.wrappedValue,
                        isFocused: false
                    )
                    .accessibilityIdentifier(accessibilityIdentifier)
            }
        }
    }
}

/// Patch values for Quick Reflection saves — `nil` means do not update that column.
struct PostTradePsychologySavePatch: Sendable {
    var confidence: Int? = nil
    var emotion: String? = nil
    var exitEmotion: String? = nil
    var executionRating: Int? = nil
    var psychologyNotes: String? = nil

    var hasAnyValue: Bool {
        if let confidence, confidence > 0 { return true }
        if let emotion, !emotion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let exitEmotion, !exitEmotion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let executionRating, executionRating > 0 { return true }
        if let psychologyNotes, !psychologyNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }
}