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
import { supabase } from "./supabaseClient"

/** Columns allowed in global client profile state — never load billing or moderation extras. */
const USER_PROFILE_SELECT =
  "id, username, avatar_url, is_pro, subscription_status, is_banned, banned_reason, referral_code, is_beta_tester" as const

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
  }
}

type UserProfileContextValue = {
  user: any
  profile: UserProfileSlice | null
  loading: boolean
  setProfile: Dispatch<SetStateAction<UserProfileSlice | null>>
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
        .single()

      if (!mounted || generation !== loadGeneration) return

      setProfileState(pickUserProfileFields(profileData))

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
    () => ({ user, profile, loading, setProfile }),
    [user, profile, loading, setProfile]
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
