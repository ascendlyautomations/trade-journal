import SwiftUI

// MARK: - TradeTraxs grouped surfaces (dark mode)
//
// Prefer these over raw `.listStyle(.insetGrouped)`, system Materials, or `.bar`.
// iOS inset-grouped rows and bar/material chrome read warm brown in dark mode unless
// we paint Dashboard-style cool blue-gray lifts via `experienceDashboardGroupedRows()`.
//
// | Use case | API |
// |----------|-----|
// | Settings / pickers (List) | `experienceInsetGroupedListStyle(pageBackground:)` |
// | Plain List (Feed-style rows) | `experiencePlainListStyle()` |
// | Form { Section { … } } | `experienceTradeTraxsFormStyle(pageBackground:)` |
// | Bottom toolbars / chrome strips | `experienceChromeBarBackground()` |
// | Floating panels (scrubbers, menus) | `experienceFloatingPanelBackground(in:)` |
// | Full-screen material fills | `experienceMaterial(_:)` (not raw MaterialToken.material) |
//
// Intentional system materials: only inside this file (light mode) and `SurfaceStyle` light branch.

extension View {
    /// Inset grouped `List` — cool row lift in dark mode; light mode unchanged.
    func experienceInsetGroupedListStyle(pageBackground: Bool = false) -> some View {
        modifier(ExperienceInsetGroupedListModifier(pageBackground: pageBackground))
    }

    /// Plain `List` on the semantic page canvas — Activity, Trades, share pickers, etc.
    func experiencePlainListStyle() -> some View {
        modifier(ExperiencePlainListModifier())
    }

    /// `Form` / grouped sections — same row treatment as inset grouped lists.
    func experienceTradeTraxsFormStyle(pageBackground: Bool = false) -> some View {
        modifier(ExperienceTradeTraxsFormModifier(pageBackground: pageBackground))
    }

    /// Bottom chrome / toolbars — opaque cool surface in dark mode; system bar in light.
    func experienceChromeBarBackground() -> some View {
        modifier(ExperienceChromeBarBackgroundModifier())
    }

    /// Chart scrubbers, floating pickers, media chrome — cool panel in dark mode; thin material in light.
    func experienceFloatingPanelBackground<S: InsettableShape>(
        in shape: S,
        borderOpacity: Double = 0.5
    ) -> some View {
        modifier(
            ExperienceFloatingPanelBackgroundModifier(
                shape: shape,
                borderOpacity: borderOpacity
            )
        )
    }
}

// MARK: - Themed material (replaces raw `.experienceMaterial` + system Material)

extension View {
    /// Semantic material — dark mode uses opaque theme surfaces; light mode uses system Material.
    func experienceMaterial(_ token: MaterialToken) -> some View {
        modifier(ExperienceThemedMaterialModifier(token: token))
    }
}

enum ExperienceThemedMaterial {
    /// Opaque semantic fill for dark mode / Reduce Transparency. Light mode returns nil (use system Material).
    static func darkSurface(
        for token: MaterialToken,
        colors: SemanticColorPalette
    ) -> Color? {
        switch token {
        case .ultraThin, .thin:
            return colors.surfaceSecondary
        case .regular:
            return colors.sheetBackground
        case .thick:
            return colors.surfacePrimary
        case .chrome:
            return colors.backgroundSecondary
        }
    }
}

private struct ExperienceInsetGroupedListModifier: ViewModifier {
    var pageBackground: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .experienceDashboardGroupedRows()
            .background {
                if pageBackground {
                    colors.groupedBackground.ignoresSafeArea()
                } else if colorScheme == .dark {
                    colors.backgroundPrimary.ignoresSafeArea()
                }
            }
    }
}

private struct ExperiencePlainListModifier: ViewModifier {
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .experienceDashboardGroupedRows()
            .background(colors.backgroundPrimary.ignoresSafeArea())
    }
}

private struct ExperienceTradeTraxsFormModifier: ViewModifier {
    var pageBackground: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .experienceDashboardGroupedRows()
            .background {
                if pageBackground {
                    colors.groupedBackground.ignoresSafeArea()
                } else if colorScheme == .dark {
                    colors.backgroundPrimary.ignoresSafeArea()
                }
            }
    }
}

private struct ExperienceChromeBarBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.background(colors.backgroundSecondary)
        } else {
            content.background(.bar)
        }
    }
}

private struct ExperienceFloatingPanelBackgroundModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let shape: S
    let borderOpacity: Double

    func body(content: Content) -> some View {
        if colorScheme == .dark || reduceTransparency {
            content
                .background(colors.surfaceSecondary, in: shape)
                .overlay {
                    shape.stroke(colors.border.opacity(borderOpacity), lineWidth: ExperienceBorder.hairline)
                }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(colors.border.opacity(borderOpacity), lineWidth: ExperienceBorder.hairline)
                }
        }
    }
}

private struct ExperienceThemedMaterialModifier: ViewModifier {
    let token: MaterialToken
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if colorScheme == .dark || reduceTransparency,
           let surface = ExperienceThemedMaterial.darkSurface(for: token, colors: colors)
        {
            content.background(surface)
        } else {
            content.background(token.material)
        }
    }
}
