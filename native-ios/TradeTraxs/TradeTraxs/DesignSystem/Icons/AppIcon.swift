import SwiftUI

/// Semantic icon catalog. Features use these — not raw SF Symbol strings.
enum AppIcon: String, CaseIterable, Sendable {
    case home = "house.fill"
    case feed = "rectangle.stack.fill"
    case create = "plus.circle.fill"
    case messages = "bubble.left.and.bubble.right.fill"
    case profile = "person.crop.circle.fill"
    case activity = "bell.fill"
    case settings = "gearshape.fill"
    case search = "magnifyingglass"
    case trades = "list.bullet.rectangle"
    case reports = "doc.text.fill"
    case calendar = "calendar"
    case rooms = "person.3.fill"
    case explore = "safari.fill"
    case leaderboard = "trophy.fill"
    case chart = "chart.line.uptrend.xyaxis"
    case grid = "circle.grid.2x2.fill"
    case textBubble = "text.bubble"
    case playRectangle = "play.rectangle"
    case trophy = "trophy"
    case camera = "camera.fill"
    case photo = "photo"
    case video = "video.fill"
    case play = "play.fill"
    case chevronDown = "chevron.down"
    case share = "square.and.arrow.up"
    case compose = "square.and.pencil"
    case filter = "line.3.horizontal.decrease.circle"
    case close = "xmark"
    case back = "chevron.left"
    case forward = "chevron.right"
    case checkmark = "checkmark"
    case warning = "exclamationmark.triangle.fill"
    case error = "xmark.octagon.fill"
    case success = "checkmark.circle.fill"
    case info = "info.circle.fill"
    case offline = "wifi.slash"
    case sync = "arrow.triangle.2.circlepath"
    case empty = "tray"
    case lock = "lock.fill"
    case sparkles = "sparkles"
    case more = "ellipsis"

    /// Future custom asset name (Asset Catalog). Nil means SF Symbol.
    var customAssetName: String? { nil }

    var systemName: String { rawValue }
}

enum IconSizeToken: CGFloat, CaseIterable, Sendable {
    case xs = 12
    case sm = 16
    case md = 20
    case lg = 24
    case xl = 28
    case xxl = 32
    case hero = 48

    var value: CGFloat { rawValue }
}

struct ExperienceIcon: View {
    let icon: AppIcon
    var size: IconSizeToken = .md
    var color: Color = ExperienceColor.textPrimary
    var accessibilityLabel: String?

    var body: some View {
        Group {
            if let asset = icon.customAssetName {
                Image(asset)
                    .resizable()
                    .renderingMode(.template)
            } else {
                Image(systemName: icon.systemName)
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size.value, height: size.value)
        .foregroundStyle(color)
        .accessibilityLabel(Text(accessibilityLabel ?? icon.rawValue))
        .accessibilityAddTraits(.isImage)
    }
}
