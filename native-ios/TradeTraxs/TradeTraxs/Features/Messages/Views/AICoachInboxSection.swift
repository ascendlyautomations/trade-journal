import SwiftUI

enum AICoachInboxFilter: String, CaseIterable, Identifiable {
    case all
    case individualTrade
    case psychology
    case general

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .all: return "All Chats"
        case .individualTrade: return "Individual Trade"
        case .psychology: return "Psychology"
        case .general: return "General"
        }
    }

    func matches(kind: String) -> Bool {
        switch self {
        case .all: return true
        case .individualTrade: return kind == "trade"
        case .psychology: return kind == "psychology"
        case .general: return kind == "general_trade"
        }
    }
}

@MainActor
@Observable
final class AICoachInboxStore {
    static let shared = AICoachInboxStore()

    private(set) var items: [TradeAIConversationInboxItem] = []
    private(set) var isLoading = false
    var filter: AICoachInboxFilter = .all

    private init() {}

    var filteredItems: [TradeAIConversationInboxItem] {
        let filtered = items.filter { filter.matches(kind: $0.kind) }
        return filtered.sorted { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
    }

    func refresh(using ai: any AIRepository) async {
        isLoading = true
        defer { isLoading = false }
        let loaded = (try? await ai.loadConversationInbox(limit: 50)) ?? []
        items = loaded.sorted { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
    }
}

/// AI coach threads on Messages home (filter + rows use DM inbox chrome).
struct AICoachInboxListSection: View {
    let ai: any AIRepository
    let detailCache: DetailPresentationCache
    let onOpen: (TradeAIConversationInboxItem) -> Void

    @Bindable private var store = AICoachInboxStore.shared
    @Environment(\.themeColors) private var colors

    var body: some View {
        if !store.items.isEmpty || store.isLoading {
            Section {
                if store.isLoading, store.items.isEmpty {
                    ExperienceIndeterminateProgress()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.vertical, ExperienceSpacing.sm)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else if store.filteredItems.isEmpty {
                    Text("No conversations in this filter.")
                        .experienceStyle(.subheadline, color: colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.vertical, ExperienceSpacing.sm)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(store.filteredItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            onOpen(item)
                        } label: {
                            AICoachInboxRowView(
                                item: item,
                                detailCache: detailCache
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.experiencePlain)
                        .messagesInboxAICoachListRowStyle(
                            colors: colors,
                            showsBottomSeparator: index < store.filteredItems.count - 1
                        )
                    }
                }
            } header: {
                AICoachInboxSectionHeader(filter: $store.filter)
                    .padding(.bottom, -MessagesInboxLayout.headerToFirstRowCompression)
            }
            .task {
                await store.refresh(using: ai)
            }
        }
    }
}

/// Legacy wrapper for previews; prefer ``AICoachInboxListSection`` in ``List``.
struct AICoachInboxSection: View {
    let ai: any AIRepository
    let detailCache: DetailPresentationCache
    let onOpen: (TradeAIConversationInboxItem) -> Void

    var body: some View {
        AICoachInboxListSection(
            ai: ai,
            detailCache: detailCache,
            onOpen: onOpen
        )
    }
}

private struct AICoachInboxSectionHeader: View {
    @Binding var filter: AICoachInboxFilter
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.xs) {
            Text("AI Coaches")
                .experienceStyle(.caption, color: colors.secondaryText)
                .textCase(.uppercase)
            Spacer(minLength: ExperienceSpacing.sm)
            Menu {
                ForEach(AICoachInboxFilter.allCases) { option in
                    Button {
                        ExperienceHaptics.play(.selection)
                        filter = option
                    } label: {
                        HStack {
                            Text(option.menuTitle)
                            if filter == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.footnote.weight(.semibold))
                    Text(filter.menuTitle)
                        .experienceStyle(.footnote, color: colors.accent)
                        .lineLimit(1)
                }
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, 6)
                .background(colors.fillSecondary, in: Capsule())
            }
            .accessibilityLabel("Filter AI coaches")
            .accessibilityValue(filter.menuTitle)
            .accessibilityIdentifier("messages.aiCoach.filter")
        }
    }
}

private struct AICoachInboxRowView: View {
    let item: TradeAIConversationInboxItem
    let detailCache: DetailPresentationCache

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: MessagesInboxLayout.rowHorizontalSpacing) {
            iconBadge
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
                    Text(primaryTitle)
                        .experienceStyle(.body, color: colors.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let timestamp = item.lastMessageAt {
                        Text(MessagesInboxSupport.relativeTimestamp(timestamp))
                            .experienceStyle(.caption, color: colors.tertiaryText)
                            .lineLimit(1)
                    }
                }
                Text(typeLabel)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .lineLimit(1)
                if let subtitle = tradeSubtitle {
                    Text(subtitle)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .lineLimit(1)
                }
                if let preview = item.preview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
                    Text(preview)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, MessagesInboxLayout.rowVerticalPadding)
        .accessibilityIdentifier("messages.aiCoach.row.\(item.id.rawValue)")
    }

    private var presentation: AICoachInboxPresentation {
        AICoachInboxPresentation(item: item, tradeSummary: tradeSummary)
    }

    private var tradeSummary: TradeSummary? {
        guard let tradeID = item.tradeID else { return nil }
        return detailCache.tradeSummary(id: tradeID)
    }

    private var primaryTitle: String {
        presentation.primaryTitle
    }

    private var typeLabel: String {
        presentation.typeLabel
    }

    private var tradeSubtitle: String? {
        presentation.tradeSubtitle
    }

    @ViewBuilder
    private var iconBadge: some View {
        Image(systemName: presentation.iconSystemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(colors.accent)
            .frame(width: 40, height: 40)
            .background(colors.fillSecondary, in: Circle())
            .accessibilityHidden(true)
    }
}

private struct AICoachInboxPresentation {
    let item: TradeAIConversationInboxItem
    let tradeSummary: TradeSummary?

    var iconSystemName: String {
        switch item.kind {
        case "trade": return "chart.candlestick"
        case "psychology": return "brain.head.profile"
        case "general_trade": return "chart.xyaxis.line"
        default: return "brain.head.profile"
        }
    }

    var typeLabel: String {
        switch item.kind {
        case "trade": return "Individual Trade"
        case "psychology": return "Psychology"
        case "general_trade": return "General"
        default: return "AI Coach"
        }
    }

    var primaryTitle: String {
        switch item.kind {
        case "trade":
            if let tradeSummary {
                return tradeSummary.symbol.ticker
            }
            return parsedTicker(from: item.title) ?? item.title ?? "Trade AI"
        case "psychology", "general_trade":
            return item.title ?? typeLabel
        default:
            return item.title ?? "AI Coach"
        }
    }

    var tradeSubtitle: String? {
        guard item.kind == "trade" else { return nil }
        if let tradeSummary {
            let side = tradeSummary.side == .long ? "Long" : "Short"
            let pnl = TradeDisplay.pnlText(tradeSummary.realizedPnL)
            return "\(side) · \(pnl)"
        }
        return nil
    }

    private func parsedTicker(from title: String?) -> String? {
        guard let title else { return nil }
        let parts = title.components(separatedBy: " · ")
        let ticker = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ticker.isEmpty ? nil : ticker
    }
}

private extension View {
    func messagesInboxAICoachListRowStyle(
        colors: SemanticColorPalette,
        showsBottomSeparator: Bool
    ) -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowBackground(colors.backgroundPrimary)
            .listRowSeparator(showsBottomSeparator ? .visible : .hidden, edges: .bottom)
            .listRowSeparatorTint(colors.separator.opacity(MessagesInboxLayout.rowSeparatorLineOpacity))
    }
}