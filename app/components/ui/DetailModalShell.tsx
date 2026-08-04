"use client"

/**
 * Detail modal shell — delegates to PlatformModal so Capacitor iOS gets
 * fullscreen native presentation while web keeps the existing card overlay.
 */
export {
  default,
  NAVBAR_HEIGHT_CLASS,
  NAVBAR_HEIGHT_REM,
  MODAL_FIXED_BELOW_NAVBAR_CLASS,
  MODAL_OVERLAY_BELOW_NAVBAR_CLASS,
  MODAL_COMPONENT_BELOW_NAVBAR_CLASS,
  type PlatformModalProps as DetailModalShellProps,
} from "@/app/components/platform/PlatformModal"

/** Scroll a modal comments list pane and focus the composer input. */
export function scrollModalCommentsPane(
  container: HTMLElement | null | undefined,
  behavior: ScrollBehavior = "smooth"
) {
  if (!container) return
  container.scrollTo({ top: container.scrollHeight, behavior })
  const input =
    container.parentElement?.querySelector("input") ??
    container.querySelector("input")
  if (input instanceof HTMLInputElement) {
    input.focus()
  }
}
