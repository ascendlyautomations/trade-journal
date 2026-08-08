import SwiftUI

/// Typography roles mapped to Dynamic Type-aware system fonts.
enum TypographyRole: String, CaseIterable, Sendable {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case body
    case callout
    case subheadline
    case footnote
    case caption
    case caption2
    case metric
    case metricLarge

    var textStyle: Font.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body: return .body
        case .callout: return .callout
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption, .metric: return .caption
        case .caption2: return .caption2
        case .metricLarge: return .title2
        }
    }

    var weight: Font.Weight {
        switch self {
        case .largeTitle, .title, .title2, .headline, .metricLarge:
            return .semibold
        case .title3, .metric:
            return .medium
        default:
            return .regular
        }
    }

    var design: Font.Design {
        switch self {
        case .metric, .metricLarge:
            return .rounded
        default:
            return .default
        }
    }

    var isMonospacedDigits: Bool {
        switch self {
        case .metric, .metricLarge:
            return true
        default:
            return false
        }
    }
}

enum ExperienceTypography {
    static func font(_ role: TypographyRole) -> Font {
        let base = Font.system(role.textStyle, design: role.design).weight(role.weight)
        return role.isMonospacedDigits ? base.monospacedDigit() : base
    }

    static let largeTitle = font(.largeTitle)
    static let title = font(.title)
    static let title2 = font(.title2)
    static let title3 = font(.title3)
    static let headline = font(.headline)
    static let body = font(.body)
    static let callout = font(.callout)
    static let subheadline = font(.subheadline)
    static let footnote = font(.footnote)
    static let caption = font(.caption)
    static let caption2 = font(.caption2)
    static let metric = font(.metric)
    static let metricLarge = font(.metricLarge)
}

struct ExperienceTextStyleModifier: ViewModifier {
    let role: TypographyRole
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(ExperienceTypography.font(role))
            .foregroundStyle(color)
    }
}

extension View {
    func experienceText(
        _ role: TypographyRole,
        color: Color = ExperienceColor.textPrimary
    ) -> some View {
        modifier(ExperienceTextStyleModifier(role: role, color: color))
    }
}

extension Text {
    func experienceStyle(
        _ role: TypographyRole,
        color: Color = ExperienceColor.textPrimary
    ) -> some View {
        experienceText(role, color: color)
    }
}
