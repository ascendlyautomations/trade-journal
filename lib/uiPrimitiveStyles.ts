/**
 * Shared UI primitive chrome — semantic theme tokens (Phase 3).
 * Used by app/components/ui/* only; pages compose these at call sites.
 */

/** Backdrop blur tracks --surface-blur per theme (0 on light). */
export const UI_THEME_BACKDROP = "ui-theme-backdrop"

/* —— Buttons (see also Button.tsx variant map) —— */

export const UI_BUTTON_PRIMARY =
  "bg-accent text-accent-foreground transition hover:bg-accent-hover disabled:hover:bg-accent"

export const UI_BUTTON_SECONDARY =
  "border border-border bg-surface-elevated text-foreground transition hover:bg-surface-secondary disabled:hover:bg-surface-elevated"

export const UI_BUTTON_GHOST =
  "bg-transparent text-foreground-secondary transition hover:bg-surface-elevated hover:text-foreground disabled:hover:bg-transparent"

/* —— Cards —— */

export const UI_CARD_GLASS =
  "rounded-xl border border-border bg-surface-elevated/50 text-card-foreground shadow-card"

export const UI_CARD_PANEL =
  "rounded-2xl border border-border bg-surface-elevated text-card-foreground shadow-elevated"

export const UI_CARD_SOLID =
  "rounded-xl border border-card-border bg-card text-card-foreground shadow-card"

export const UI_CARD_INTERACTIVE =
  "cursor-pointer transition hover:border-border hover:bg-surface-secondary"

/* —— Modals —— */

export const UI_MODAL_BACKDROP = "absolute inset-0 bg-overlay ui-theme-backdrop"

export const UI_MODAL_PANEL_SURFACE =
  "bg-card text-card-foreground ui-theme-backdrop"

export const UI_MODAL_PANEL_SHELL = `flex flex-col overflow-hidden rounded-xl border border-border shadow-modal ${UI_MODAL_PANEL_SURFACE}`

export const UI_MODAL_HEADER = "shrink-0 border-b border-divider"

export const UI_MODAL_FOOTER = `shrink-0 border-t border-divider ${UI_MODAL_PANEL_SURFACE}`

export const UI_MODAL_TITLE = "text-lg font-semibold text-foreground"

export const UI_MODAL_CLOSE_BUTTON =
  "inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-md bg-surface-elevated px-2.5 py-1.5 text-sm font-medium text-foreground opacity-90 transition hover:opacity-100 hover:bg-surface-secondary focus:outline-none focus-visible:ring-2 focus-visible:ring-focus-ring disabled:cursor-not-allowed disabled:opacity-50 md:h-auto md:w-auto md:min-h-0 md:min-w-0"

/* —— Dropdown —— */

export const UI_DROPDOWN_MENU =
  "fixed z-[10070] min-w-[10.5rem] overflow-hidden rounded-lg border border-border bg-surface-secondary py-1 shadow-elevated"

export const UI_DROPDOWN_ITEM =
  "flex w-full items-center px-3 py-2 text-left text-sm text-foreground transition hover:bg-surface-elevated"

export const UI_DROPDOWN_ITEM_DISABLED = "cursor-default text-muted-foreground"

export const UI_DROPDOWN_ITEM_DANGER =
  "flex w-full items-center px-3 py-2 text-left text-sm text-negative transition hover:bg-negative-soft"

/* —— Empty state —— */

export const UI_EMPTY_STATE_SHELL =
  "flex flex-col items-center justify-center rounded-xl border border-border bg-surface-elevated/50 px-6 py-10 text-center"

export const UI_EMPTY_STATE_ICON =
  "mb-3 flex h-10 w-10 items-center justify-center rounded-full border border-border bg-surface-secondary text-lg text-muted-foreground"

/* —— Skeleton —— */

export const UI_SKELETON_PULSE = "animate-pulse rounded-md bg-surface-elevated"

export const UI_SKELETON_CARD =
  "rounded-xl border border-border bg-surface-elevated/50 p-4 ui-theme-backdrop"

/* —— Toast (status borders/backgrounds — semantic status tokens) —— */

export const UI_TOAST_BASE =
  "pointer-events-auto flex w-full max-w-sm items-start gap-3 rounded-xl border px-4 py-3 ui-theme-backdrop transition-all duration-300 ease-out"

export const UI_TOAST_SUCCESS =
  "border-positive/40 bg-positive-soft text-foreground shadow-card"

export const UI_TOAST_ERROR =
  "border-negative/40 bg-negative-soft text-foreground shadow-card"

export const UI_TOAST_INFO = "border-info/40 bg-info-soft text-foreground shadow-card"

export const UI_TOAST_WARNING =
  "border-warning/40 bg-warning-soft text-foreground shadow-card"

export const UI_TOAST_DISMISS =
  "shrink-0 rounded p-1 text-xs text-muted-foreground transition hover:bg-surface-elevated hover:text-foreground"

/* —— Form controls —— */

export const UI_INPUT_BASE =
  "w-full rounded-lg border border-input-border bg-input text-input-foreground placeholder:text-placeholder transition focus:outline-none focus:ring-2 focus:ring-focus-ring disabled:cursor-not-allowed disabled:opacity-60"

export const UI_INPUT_ERROR = "border-negative focus:ring-negative/40"

export const UI_FEEDBACK_MODAL_PANEL_BASE =
  "relative w-full max-w-sm rounded-xl border bg-card px-6 py-5 text-center shadow-modal ui-theme-backdrop"

export const UI_FEEDBACK_MODAL_DISMISS =
  "mt-4 rounded-lg border border-border bg-surface-elevated px-4 py-2 text-sm font-medium text-foreground transition hover:bg-surface-secondary"
