/** Shared phone-only dashboard analytics presentation classes. */

export const mwDashText = {
  primary: "text-[color:var(--tt-text,#f0f3f6)]",
  muted: "text-[color:var(--tt-text-muted,#c0cad6)]",
  tertiary: "text-[color:var(--tt-text-tertiary,#a8b3c2)]",
  positive: "text-[color:var(--tt-positive,#3ddc97)]",
  negative: "text-[color:var(--tt-negative,#ff7b72)]",
  accent: "text-[color:var(--tt-accent,#4ec4e0)]",
  warning: "text-[color:var(--tt-warning,#e3b341)]",
} as const

export const mwDashFill =
  "bg-[color:var(--tt-surface-nested,#1a222c)]"

export function mwDashMoneyClass(value: number | null | undefined): string {
  if (value == null || !Number.isFinite(value) || value === 0) {
    return mwDashText.primary
  }
  return value > 0 ? mwDashText.positive : mwDashText.negative
}
