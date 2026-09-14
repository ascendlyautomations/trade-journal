/**
 * Web navigation chrome — semantic theme classes (Phase 2).
 * Shared by app Navbar and PublicNavbar shell styling.
 */

export const NAV_CHROME_FIXED_ROOT =
  "fixed left-0 top-0 z-[9999] w-full bg-chrome pt-[var(--safe-area-top)] text-chrome-foreground"

export const NAV_CHROME_BAR =
  "flex h-16 w-full shrink-0 items-center border-b border-chrome-border bg-chrome"

/** Marketing public nav uses a subtler header rule (was border-white/5). */
export const NAV_CHROME_BAR_SUBTLE_BORDER =
  "flex h-16 w-full shrink-0 items-center border-b border-border-subtle bg-chrome"

export const NAV_CHROME_MOBILE_SCROLL =
  "min-h-0 flex-1 overflow-y-auto overscroll-y-contain border-t border-chrome-border bg-chrome md:hidden"

export const NAV_PUBLIC_MOBILE_MENU =
  "max-h-[calc(100dvh-var(--app-header-offset))] w-full overflow-y-auto overscroll-y-contain border-t border-border-subtle bg-chrome md:hidden"

export const NAV_ITEM_ACTIVE = "bg-accent-soft text-info"

export const NAV_ITEM_INACTIVE =
  "text-foreground-secondary hover:text-chrome-foreground"

export const NAV_ITEM_INACTIVE_HOVER_SURFACE =
  "text-foreground-secondary hover:bg-surface-elevated"

export const NAV_ITEM_MUTED_HOVER_SURFACE =
  "text-muted-foreground hover:bg-surface-elevated"

export const NAV_LINK_SECONDARY_HOVER_ACCENT =
  "text-foreground-secondary hover:text-nav-link-hover"

export const NAV_DROPDOWN_PANEL =
  "absolute top-full z-[9999] mt-2 w-56 rounded border border-border bg-surface-secondary shadow-lg"

export const NAV_ACCOUNT_DROPDOWN_PANEL =
  "absolute right-0 top-full z-50 mt-2 w-52 rounded-lg border border-border bg-surface-secondary shadow-lg"

export const NAV_MENU_ROW =
  "w-full px-4 py-2 text-left text-sm hover:bg-surface-elevated"

export const NAV_MENU_ROW_DESTRUCTIVE =
  "w-full px-4 py-2 text-left text-sm text-destructive hover:bg-negative-soft"

export const NAV_DIVIDER = "border-t border-border"

export const NAV_SECTION_LABEL =
  "text-[10px] font-medium uppercase tracking-wide text-muted-foreground"

export const NAV_UNREAD_BADGE =
  "rounded-full bg-destructive px-1.5 py-0.5 text-xs tabular-nums text-destructive-foreground"

export const NAV_UNREAD_BADGE_ABSOLUTE =
  "absolute -right-2 -top-1 min-w-[1.25rem] rounded-full bg-destructive px-1.5 py-0.5 text-center text-xs tabular-nums text-destructive-foreground"

export const NAV_CTA_PRIMARY =
  "rounded bg-accent text-sm font-medium text-accent-foreground transition hover:bg-accent-hover"

export const NAV_CTA_PRIMARY_MD =
  "inline-flex shrink-0 rounded bg-accent px-4 py-1.5 text-sm font-medium text-accent-foreground transition hover:bg-accent-hover"

export const NAV_SKELETON_PULSE = "animate-pulse rounded-full bg-surface-elevated"
