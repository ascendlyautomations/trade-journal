import SwiftUI

extension Binding where Value == String {
    /// Applies live thousands-separator formatting on each edit.
    func numericInput(_ style: NumericInputStyle) -> Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                wrappedValue = NumericInputFieldSupport.formatWhileEditing(newValue, style: style)
            }
        )
    }
}
