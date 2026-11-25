import SwiftUI

enum TradingRulesPlannedTimePickerLayout {
    static let expandedScrollTailClearance: CGFloat = 220

    static func scrollAnchorID(for field: TradingAnalyticsPreferencesViewModel.DraftField) -> String {
        switch field {
        case .startTime: return "settings.tradingAnalytics.plannedStart"
        case .endTime: return "settings.tradingAnalytics.plannedEnd"
        default: return "settings.tradingAnalytics.plannedTime"
        }
    }

    /// Positions the field + wheel above the tab bar when the scroll view auto-scrolls.
    static let scrollRevealAnchor = UnitPoint(x: 0.5, y: 0.42)
}

/// Planned start / end times on Trading Rules — same wheel picker as Add Trade, bound to `HH:mm` draft strings.
struct TradingRulesPlannedTimePicker: View {
    let title: String
    let info: TradingRulesFieldInfo
    @Binding var timeText: String
    let field: TradingAnalyticsPreferencesViewModel.DraftField
    @Binding var expandedField: TradingAnalyticsPreferencesViewModel.DraftField?
    let scrollAnchorID: String

    @State private var selection = Date()
    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { expandedField == field }

    var body: some View {
        VStack(alignment: .leading, spacing: TradingPreferenceFormLayout.fieldStackSpacing) {
            TradingRulesFieldLabel(title: title, info: info)
            Button {
                toggleExpanded()
            } label: {
                Text(displayLabel)
                    .font(.subheadline)
                    .foregroundStyle(timeText.isEmpty ? colors.tertiaryText : colors.primaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .tradingRulesInsetControl()
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("\(title), \(displayLabel)")
            .accessibilityIdentifier(scrollAnchorID)

            if isExpanded {
                VStack(spacing: ExperienceSpacing.xs) {
                    DatePicker(
                        title,
                        selection: $selection,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.timeZone, AddTradeWheelTimePickerSupport.easternCalendar.timeZone)
                    .frame(maxWidth: .infinity)
                    .background(colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))

                    HStack {
                        Button("Clear") {
                            timeText = ""
                            collapse()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.secondaryText)
                        Spacer()
                        Button("Done") {
                            collapse()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.accent)
                    }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(scrollAnchorID)
        .onAppear { syncSelectionFromText() }
        .onChange(of: timeText) { _, _ in
            if !isExpanded {
                syncSelectionFromText()
            }
        }
        .onChange(of: selection) { _, newValue in
            guard isExpanded else { return }
            let calendar = AddTradeWheelTimePickerSupport.easternCalendar
            let hour = calendar.component(.hour, from: newValue)
            let minute = calendar.component(.minute, from: newValue)
            timeText = AddTradeWheelTimePickerSupport.clockString(minutes: hour * 60 + minute)
        }
    }

    private var displayLabel: String {
        let trimmed = timeText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let minutes = AddTradeWheelTimePickerSupport.minutes(fromClock: trimmed) else {
            return "Set time"
        }
        return AddTradeWheelTimePickerSupport.shortTimeLabel(minutes: minutes)
    }

    private func toggleExpanded() {
        if isExpanded {
            collapse()
        } else {
            if expandedField != field {
                expandedField = field
            }
            syncSelectionFromText()
        }
    }

    private func collapse() {
        if expandedField == field {
            expandedField = nil
        }
    }

    private func syncSelectionFromText() {
        if let minutes = AddTradeWheelTimePickerSupport.minutes(fromClock: timeText) {
            selection = AddTradeWheelTimePickerSupport.date(forMinutes: minutes)
        } else {
            selection = AddTradeWheelTimePickerSupport.date(forMinutes: 9 * 60 + 30)
        }
    }
}