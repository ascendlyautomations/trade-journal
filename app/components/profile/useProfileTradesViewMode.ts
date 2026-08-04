"use client"

import { useCallback, useEffect, useState } from "react"

export const PROFILE_TRADES_VIEW_MODES = ["grid", "list"] as const

export type ProfileTradesViewMode = (typeof PROFILE_TRADES_VIEW_MODES)[number]

const STORAGE_KEY = "tt-profile-trades-view"

function isProfileTradesViewMode(value: unknown): value is ProfileTradesViewMode {
  return value === "grid" || value === "list"
}

/** Mobile Profile Trades tab: default Grid; remember last Grid | List choice. */
export function useProfileTradesViewMode() {
  const [viewMode, setViewModeState] = useState<ProfileTradesViewMode>("grid")

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY)
      if (isProfileTradesViewMode(raw)) setViewModeState(raw)
    } catch {
      /* ignore */
    }
  }, [])

  const setViewMode = useCallback((next: ProfileTradesViewMode) => {
    setViewModeState(next)
    try {
      window.localStorage.setItem(STORAGE_KEY, next)
    } catch {
      /* ignore */
    }
  }, [])

  return { viewMode, setViewMode }
}
