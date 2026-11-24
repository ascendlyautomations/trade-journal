import SwiftUI

/// First step: method selection (OBS only on iOS).
struct TradeRoomStartStreamSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    /// Single option, kept as a picker per product spec.
    @State private var method: String = "obs"
    @State private var streamTitle: String = ""

    var onConfirmOBS: (String) -> Void

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

                Section("Stream title") {
                    TextField("e.g. Trading NY Session, NQ Futures", text: $streamTitle)
                        .textInputAutocapitalization(.sentences)
                    Text("\(streamTitle.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(TradeRoomBroadcastStreamTitle.maxLength)")
                        .font(.caption2)
                        .foregroundStyle(colors.textSecondary)
                }

                Section {
                    Button("Start with OBS") {
                        guard let title = TradeRoomBroadcastStreamTitle.normalize(streamTitle) else { return }
                        onConfirmOBS(title)
                    }
                    .fontWeight(.semibold)
                    .disabled(TradeRoomBroadcastStreamTitle.normalize(streamTitle) == nil)
                }
            }
            .experienceTradeTraxsFormStyle(pageBackground: true)
            .navigationTitle("Start a stream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .experienceSheetChrome(detents: [.large])
    }
}
