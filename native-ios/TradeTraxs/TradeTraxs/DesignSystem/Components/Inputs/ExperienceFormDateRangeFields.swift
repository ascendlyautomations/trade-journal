import SwiftUI

/// Start/end date rows for themed ``Form`` sheets (Reports custom range, activity filters, etc.).
struct ExperienceFormDateRangeFields: View {
    @Binding var start: Date
    @Binding var end: Date
    var maximumDate: Date = Date()
    var startLabel: LocalizedStringKey = "Start Date"
    var endLabel: LocalizedStringKey = "End Date"

    @Environment(\.themeColors) private var colors

    var body: some View {
        DatePicker(startLabel, selection: $start, in: ...maximumDate, displayedComponents: .date)
            .datePickerStyle(.compact)
            .tint(colors.accent)
        DatePicker(endLabel, selection: $end, in: ...maximumDate, displayedComponents: .date)
            .datePickerStyle(.compact)
            .tint(colors.accent)
    }
}