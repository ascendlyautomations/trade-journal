import type { ContextualTourTargetId } from "./types"

export const CONTEXTUAL_TOUR_NAV_MENU_EVENT = "tt-contextual-tour-nav-menu"

export type ContextualTourNavMenuDetail = {
  menu: "community" | "analytics" | "more"
  /** Mobile drawer: open hamburger so nav targets can measure. */
  openMobileNav?: boolean
}

function shouldOpenMobileNavForTour(): boolean {
  if (typeof window === "undefined") return false
  return window.matchMedia("(max-width: 767px)").matches
}

export function dispatchContextualTourNavMenu(
  detail: ContextualTourNavMenuDetail
): void {
  if (typeof window === "undefined") return
  window.dispatchEvent(
    new CustomEvent(CONTEXTUAL_TOUR_NAV_MENU_EVENT, {
      detail: {
        ...detail,
        openMobileNav:
          detail.openMobileNav === true && shouldOpenMobileNavForTour(),
      },
    })
  )
}

export function prepareTourNavForTarget(target: ContextualTourTargetId): void {
  switch (target) {
    case "feedTradeRooms":
    case "feedExplore":
      dispatchContextualTourNavMenu({ menu: "community", openMobileNav: true })
      break
    default:
      break
  }
}
