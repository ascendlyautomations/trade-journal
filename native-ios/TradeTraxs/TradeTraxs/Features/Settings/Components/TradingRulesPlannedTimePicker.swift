import SwiftUI

enum TradingRulesPlannedTimePickerLayout {
    static func scrollAnchorID(for field: TradingAnalyticsPreferencesViewModel.DraftField) -> String {
        switch field {
        case .startTime: return "settings.tradingAnalytics.plannedStart"
        case .endTime: return "settings.tradingAnalytics.plannedEnd"
        default: return "settings.tradingAnalytics.plannedTime"
        }
    }
}

/// Planned start / end times on Trading Rules — compact wheel sheet, `HH:mm` draft strings.
struct TradingRulesPlannedTimePicker: View {
    let title: String
    let info: TradingRulesFieldInfo
    @Binding var timeText: String
    let field: TradingAnalyticsPreferencesViewModel.DraftField
    @Binding var expandedField: TradingAnalyticsPreferencesViewModel.DraftField?
    let scrollAnchorID: String

    @State private var selection = Date()
    @Environment(\.themeColors) private var colors

    private var showsSheet: Bool { expandedField == field }

    private var sheetPresented: Binding<Bool> {
        Binding(
            get: { expandedField == field },
            set: { isPresented in
                if !isPresented {
                    collapse()
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TradingPreferenceFormLayout.fieldStackSpacing) {
            TradingRulesFieldLabel(title: title, info: info)
            Button {
                presentSheet()
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(scrollAnchorID)
        .onAppear { syncSelectionFromText() }
        .onChange(of: timeText) { _, _ in
            if !showsSheet {
                syncSelectionFromText()
            }
        }
        .onChange(of: selection) { _, newValue in
            guard showsSheet else { return }
            let calendar = AddTradeWheelTimePickerSupport.easternCalendar
            let hour = calendar.component(.hour, from: newValue)
            let minute = calendar.component(.minute, from: newValue)
            timeText = AddTradeWheelTimePickerSupport.clockString(minutes: hour * 60 + minute)
        }
        .sheet(isPresented: sheetPresented) {
            AddTradeWheelTimePickerSheet(
                title: title,
                selection: $selection,
                onClear: {
                    timeText = ""
                    collapse()
                },
                onDone: { collapse() }
            )
        }
    }

    private var displayLabel: String {
        let trimmed = timeText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let minutes = AddTradeWheelTimePickerSupport.minutes(fromClock: trimmed) else {
            return "Set time"
        }
        return AddTradeWheelTimePickerSupport.shortTimeLabel(minutes: minutes)
    }

    private func presentSheet() {
        if expandedField != field {
            expandedField = field
        }
        syncSelectionFromText()
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