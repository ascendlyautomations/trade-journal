import { disableDemoMode, exitDemoMode } from "./demo/demoMode"
import { finalizeGuestSession, issueGuestSession } from "./guestSessionClient"
import {
  isShowcaseUserId,
  showcaseProfilePath,
  SHOWCASE_USER_ID,
} from "./guestShowcaseAccount"
import { profilePath } from "./profileRoutes"
import { supabase } from "./supabaseClient"

export const GUEST_EXPLORE_STORAGE_KEY = "tradetraxs_guest_explore"
export const GUEST_EXPLORE_CHANGE_EVENT = "tradetraxs-guest-explore"

export function isGuestExploreActive(): boolean {
  if (typeof window === "undefined") return false
  return sessionStorage.getItem(GUEST_EXPLORE_STORAGE_KEY) === "1"
}

function markGuestExploreActive(): void {
  if (typeof window === "undefined") return
  sessionStorage.setItem(GUEST_EXPLORE_STORAGE_KEY, "1")
  window.dispatchEvent(new Event(GUEST_EXPLORE_CHANGE_EVENT))
}

export function clearGuestExploreActive(): void {
  if (typeof window === "undefined") return
  sessionStorage.removeItem(GUEST_EXPLORE_STORAGE_KEY)
  window.dispatchEvent(new Event(GUEST_EXPLORE_CHANGE_EVENT))
}

export { isShowcaseUserId, SHOWCASE_USER_ID, showcaseProfilePath }

/** Logged-out Explore as Guest — not a real member session (marketing/auth UX). */
export function isGuestExploreViewer(
  user: { id: string } | null | undefined
): boolean {
  if (isGuestExploreActive()) return true
  return isShowcaseUserId(user?.id ?? null)
}

/** Open (or reopen) the showcase profile without treating the viewer as signed in. */
export function resumeGuestExploreNavigation(): void {
  if (typeof window === "undefined") return
  window.location.assign(showcaseProfilePath())
}

export type EnterGuestExploreResult =
  | { ok: true; profileHref: string }
  | { ok: false; error: "unavailable" | "session" | "profile" }

async function resolveShowcaseProfileHref(userId: string): Promise<string> {
  try {
    const { data, error } = await supabase
      .from("profiles")
      .select("id, username")
      .eq("id", userId)
      .maybeSingle()
    if (!error && data) {
      return profilePath(data)
    }
  } catch {
    /* fall through */
  }
  return showcaseProfilePath()
}

/**
 * Logged-out Explore the Demo — same issuer path as iOS Explore as Guest.
 * Installs a showcase Supabase session and returns the profile URL to open.
 */
export async function enterGuestExplore(): Promise<EnterGuestExploreResult> {
  exitDemoMode()
  disableDemoMode()

  const issued = await issueGuestSession()
  if (typeof issued === "string") {
    return { ok: false, error: "unavailable" }
  }

  const { error } = await supabase.auth.setSession({
    access_token: issued.accessToken,
    refresh_token: issued.refreshToken,
  })
  if (error) {
    return { ok: false, error: "session" }
  }

  const finalized = await finalizeGuestSession(issued.accessToken)
  if (!finalized) {
    await supabase.auth.signOut()
    return { ok: false, error: "session" }
  }

  markGuestExploreActive()

  const profileHref = await resolveShowcaseProfileHref(issued.userId)
  return { ok: true, profileHref }
}

/** Leave guest explore — clears the flag and signs out the showcase session. */
export async function exitGuestExplore(): Promise<void> {
  clearGuestExploreActive()
  const { data } = await supabase.auth.getSession()
  if (isShowcaseUserId(data.session?.user?.id ?? null)) {
    await supabase.auth.signOut()
  }
}
