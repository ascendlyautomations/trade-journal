import type { ContextualTourTargetId } from "./types"

export type ContextualTourSettingsTabId =
  | "appearance"
  | "broker-integrations"

export const CONTEXTUAL_TOUR_SETTINGS_TAB_EVENT = "tt-contextual-tour-settings-tab"

export function settingsTabForTourTarget(
  target: ContextualTourTargetId
): ContextualTourSettingsTabId | null {
  switch (target) {
    case "settingsAppearance":
      return "appearance"
    case "settingsBroker":
      return "broker-integrations"
    default:
      return null
  }
}

export function dispatchContextualTourSettingsTab(
  tab: ContextualTourSettingsTabId
): void {
  if (typeof window === "undefined") return
  window.dispatchEvent(
    new CustomEvent(CONTEXTUAL_TOUR_SETTINGS_TAB_EVENT, { detail: { tab } })
  )
}
