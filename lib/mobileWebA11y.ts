/** Move focus inside a phone-web dialog without leaving the dialog. */
export function nextDialogFocusIndex(
  current: number,
  count: number,
  shift: boolean
): number {
  if (count <= 1) return 0
  if (shift) return current <= 0 ? count - 1 : current - 1
  return current >= count - 1 ? 0 : current + 1
}

const FOCUSABLE_SELECTOR = [
  "a[href]",
  "button:not([disabled])",
  "textarea:not([disabled])",
  "input:not([disabled]):not([type='hidden'])",
  "select:not([disabled])",
  "[tabindex]:not([tabindex='-1'])",
].join(", ")

export function phoneWebDialogFocusables(root: ParentNode): HTMLElement[] {
  return [...root.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)].filter(
    (element) => {
      if (element.getAttribute("aria-hidden") === "true") return false
      return element.getClientRects().length > 0
    }
  )
}
