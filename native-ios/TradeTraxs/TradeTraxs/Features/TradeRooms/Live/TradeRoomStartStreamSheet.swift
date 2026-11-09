import SwiftUI

/// First step: method selection (OBS only on iOS).
struct TradeRoomStartStreamSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    /// Single option — kept as a picker per product spec.
    @State private var method: String = "obs"

    var onConfirmOBS: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Streaming method", selection: $method) {
                        Text("OBS Studio").tag("obs")
                    }
                    Text("Other streaming methods are available on web.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                }

                Section {
                    Button("Start with OBS") {
                        onConfirmOBS()
                    }
                    .fontWeight(.semibold)
                }
            }
            .navigationTitle("Start a stream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
