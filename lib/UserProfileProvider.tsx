"use client"

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  type Dispatch,
  type ReactNode,
  type SetStateAction,
} from "react"
import type { AuthChangeEvent, Session } from "@supabase/supabase-js"
import {
  applyBetaReferralIfEligible,
  clearBetaReferralAfterApply,
} from "./applyBetaReferralIfEligible"
import { isBetaReferralRef } from "./betaReferralCode"
import {
  ensureProfileForUser,
  readStoredReferralCode,
} from "./ensureProfileForUser"
import { supabase } from "./supabaseClient"
import { clearAppDataCache } from "./appDataCache"
import { invalidateExploreSession } from "./exploreSessionCache"
import { clearFeedSessionsForUser } from "./feedSessionCache"
import { clearConversationSessionsForUser } from "./conversationSessionCache"
import { clearImageUrlCache } from "./imageUrlCache"
import { invalidateStoriesSession } from "./storiesSessionCache"
import { resetRoutePrefetchSession } from "./routePrefetch"

/**
 * Shared profile columns for shell + dashboard + getting-started.
 * Avoids duplicate `profiles` reads across Navbar, checklist, and key pages.
 */
export const USER_PROFILE_SELECT =
  "id, username, avatar_url, is_pro, subscription_status, is_banned, banned_reason, referral_code, is_beta_tester, onboarding_completed, has_seen_getting_started_intro, has_seen_onboarding_complete_popup, bio, trading_style, trader_type, primary_market, started_trading, max_drawdown_limit, is_private" as const

export type UserProfileSlice = {
  id: string
  username: string | null
  avatar_url: string | null
  is_pro: boolean | null
  subscription_status: string | null
  is_banned: boolean | null
  banned_reason: string | null
  referral_code: string | null
  is_beta_tester: boolean | null
  onboarding_completed: boolean | null
  has_seen_getting_started_intro: boolean | null
  has_seen_onboarding_complete_popup: boolean | null
  bio: string | null
  trading_style: string | null
  trader_type: string | null
  primary_market: string | null
  started_trading: string | null
  max_drawdown_limit: number | null
  is_private: boolean | null
}

function pickUserProfileFields(row: unknown): UserProfileSlice | null {
  if (!row || typeof row !== "object") return null
  const o = row as Record<string, unknown>
  const id = o.id
  if (typeof id !== "string" || !id.trim()) return null

  return {
    id,
    username: o.username != null ? String(o.username) : null,
    avatar_url: o.avatar_url != null ? String(o.avatar_url) : null,
    is_pro: typeof o.is_pro === "boolean" ? o.is_pro : null,
    subscription_status:
      o.subscription_status != null ? String(o.subscription_status) : null,
    is_banned: typeof o.is_banned === "boolean" ? o.is_banned : null,
    banned_reason: o.banned_reason != null ? String(o.banned_reason) : null,
    referral_code: o.referral_code != null ? String(o.referral_code) : null,
    is_beta_tester: typeof o.is_beta_tester === "boolean" ? o.is_beta_tester : null,
    onboarding_completed:
      typeof o.onboarding_completed === "boolean" ? o.onboarding_completed : null,
    has_seen_getting_started_intro:
      typeof o.has_seen_getting_started_intro === "boolean"
        ? o.has_seen_getting_started_intro
        : null,
    has_seen_onboarding_complete_popup:
      typeof o.has_seen_onboarding_complete_popup === "boolean"
        ? o.has_seen_onboarding_complete_popup
        : null,
    bio: o.bio != null ? String(o.bio) : null,
    trading_style: o.trading_style != null ? String(o.trading_style) : null,
    trader_type: o.trader_type != null ? String(o.trader_type) : null,
    primary_market: o.primary_market != null ? String(o.primary_market) : null,
    started_trading: o.started_trading != null ? String(o.started_trading) : null,
    max_drawdown_limit: (() => {
      const v = o.max_drawdown_limit
      if (v == null || v === "") return null
      const n = typeof v === "number" ? v : Number(v)
      return Number.isFinite(n) ? n : null
    })(),
    is_private: typeof o.is_private === "boolean" ? o.is_private : null,
  }
}

type UserProfileContextValue = {
  user: any
  profile: UserProfileSlice | null
  loading: boolean
  setProfile: Dispatch<SetStateAction<UserProfileSlice | null>>
  /** Re-fetch shared profile slice from Supabase (e.g. after ensure-profile upsert). */
  refreshProfile: () => Promise<void>
}

const UserProfileContext = createContext<UserProfileContextValue | null>(null)

const AUTH_SYNC_EVENTS: AuthChangeEvent[] = [
  "INITIAL_SESSION",
  "SIGNED_IN",
]

export function UserProfileProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<any>(null)
  const [profile, setProfileState] = useState<UserProfileSlice | null>(null)
  const [loading, setLoading] = useState(true)
  const realtimeTopicSuffix = useId().replace(/:/g, "")
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null)
  const profileRef = useRef<UserProfileSlice | null>(null)
  const sessionUserIdRef = useRef<string | null>(null)
  profileRef.current = profile

  const setProfile = useCallback<Dispatch<SetStateAction<UserProfileSlice | null>>>(
    (action) => {
      setProfileState((prev) => {
        const next = typeof action === "function" ? action(prev) : action
        if (next == null) return null
        return pickUserProfileFields(next)
      })
    },
    []
  )

  const refreshProfile = useCallback(async () => {
    const userId = user?.id ?? profileRef.current?.id
    if (!userId) return

    const { data: profileData } = await supabase
      .from("profiles")
      .select(USER_PROFILE_SELECT)
      .eq("id", userId)
      .maybeSingle()

    const picked = pickUserProfileFields(profileData)
    if (picked) setProfileState(picked)
  }, [user?.id])

  useEffect(() => {
    let mounted = true
    let loadGeneration = 0

    const removeProfileChannel = () => {
      const ch = channelRef.current
      channelRef.current = null
      if (ch) {
        void supabase.removeChannel(ch)
      }
    }

    const clearAuthState = () => {
      loadGeneration += 1
      removeProfileChannel()
      const signedOutUserId = sessionUserIdRef.current
      sessionUserIdRef.current = null
      clearAppDataCache()
      invalidateExploreSession()
      invalidateStoriesSession()
      clearImageUrlCache()
      resetRoutePrefetchSession()
      if (signedOutUserId) {
        clearFeedSessionsForUser(signedOutUserId)
        clearConversationSessionsForUser(signedOutUserId)
      }
      if (!mounted) return
      setUser(null)
      setProfileState(null)
      setLoading(false)
    }

    async function applyAuthSession(session: Session | null) {
      const generation = ++loadGeneration

      if (!profileRef.current) {
        setLoading(true)
      }

      removeProfileChannel()

      const sessionUser = session?.user ?? null

      if (!mounted || generation !== loadGeneration) return

      sessionUserIdRef.current = sessionUser?.id ?? null
      setUser(sessionUser)

      if (!sessionUser) {
        setProfileState(null)
        setLoading(false)
        return
      }

      const { data: profileData } = await supabase
        .from("profiles")
        .select(USER_PROFILE_SELECT)
        .eq("id", sessionUser.id)
        .maybeSingle()

      let resolvedProfile = profileData
      const storedBetaRef = isBetaReferralRef(readStoredReferralCode())

      if (!resolvedProfile) {
        const ensureResult = await ensureProfileForUser(supabase, {
          userId: sessionUser.id,
          name: null,
          referredBy: readStoredReferralCode(),
          userMetadata: sessionUser.user_metadata,
        })

        if (ensureResult.ok) {
          const { data: refetched } = await supabase
            .from("profiles")
            .select(USER_PROFILE_SELECT)
            .eq("id", sessionUser.id)
            .maybeSingle()
          resolvedProfile = refetched
          if (refetched && storedBetaRef) {
            clearBetaReferralAfterApply(refetched.is_beta_tester)
          }
        } else if (ensureResult.error) {
          console.error("ensureProfileForUser:", ensureResult.error)
        }
      } else if (storedBetaRef) {
        const repair = await applyBetaReferralIfEligible(supabase, sessionUser.id)
        if (repair.applied) {
          const { data: refetched } = await supabase
            .from("profiles")
            .select(USER_PROFILE_SELECT)
            .eq("id", sessionUser.id)
            .maybeSingle()
          if (refetched) resolvedProfile = refetched
        } else {
          clearBetaReferralAfterApply(resolvedProfile.is_beta_tester)
        }
      }

      if (!mounted || generation !== loadGeneration) return

      setProfileState(pickUserProfileFields(resolvedProfile))

      // Realtime: create channel → register .on handlers → subscribe() last (required by supabase-js).
      const topic = `profile:${sessionUser.id}:${realtimeTopicSuffix}`
      const ch = supabase.channel(topic)
      channelRef.current = ch

      ch.on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "profiles",
          filter: `id=eq.${sessionUser.id}`,
        },
        (payload) => {
          if (!mounted || generation !== loadGeneration) return
          const picked = pickUserProfileFields(payload.new)
          if (picked) setProfileState(picked)
        }
      )

      if (!mounted || generation !== loadGeneration) {
        void supabase.removeChannel(ch)
        channelRef.current = null
        return
      }

      ch.subscribe()

      if (mounted && generation === loadGeneration) {
        setLoading(false)
      }
    }

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, session) => {
      if (!mounted) return

      if (event === "SIGNED_OUT") {
        clearAuthState()
        return
      }

      if (AUTH_SYNC_EVENTS.includes(event)) {
        const nextUserId = session?.user?.id ?? null
        // Supabase emits SIGNED_IN on tab focus for session recovery — skip full
        // profile reload when the signed-in user is unchanged (matches DMs/Rooms).
        if (
          event === "SIGNED_IN" &&
          nextUserId &&
          nextUserId === sessionUserIdRef.current &&
          profileRef.current
        ) {
          return
        }
        void applyAuthSession(session)
      }
    })

    return () => {
      mounted = false
      loadGeneration += 1
      subscription.unsubscribe()
      removeProfileChannel()
    }
  }, [realtimeTopicSuffix])

  useEffect(() => {
    let cancelled = false

    async function refetchProfileAfterCheckout() {
      if (typeof window === "undefined") return
      const params = new URLSearchParams(window.location.search)
      if (params.get("checkout") !== "success") return

      const {
        data: { session },
      } = await supabase.auth.getSession()
      const userId = session?.user?.id
      if (!userId || cancelled) return

      const { data: profileData } = await supabase
        .from("profiles")
        .select(USER_PROFILE_SELECT)
        .eq("id", userId)
        .single()

      if (!cancelled && profileData) {
        const picked = pickUserProfileFields(profileData)
        if (picked) setProfileState(picked)
      }
    }

    void refetchProfileAfterCheckout()

    return () => {
      cancelled = true
    }
  }, [])

  const value = useMemo(
    () => ({ user, profile, loading, setProfile, refreshProfile }),
    [user, profile, loading, setProfile, refreshProfile]
  )

  return (
    <UserProfileContext.Provider value={value}>{children}</UserProfileContext.Provider>
  )
}

export function useUserProfile() {
  const context = useContext(UserProfileContext)
  if (!context) {
    throw new Error("useUserProfile must be used within UserProfileProvider")
  }
  return context
}
