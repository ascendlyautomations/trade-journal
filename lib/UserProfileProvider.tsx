"use client"

import {
  createContext,
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
import type { AuthChangeEvent } from "@supabase/supabase-js"
import { supabase } from "./supabaseClient"

type UserProfileContextValue = {
  user: any
  profile: any
  loading: boolean
  setProfile: Dispatch<SetStateAction<any>>
}

const UserProfileContext = createContext<UserProfileContextValue | null>(null)

const AUTH_SYNC_EVENTS: AuthChangeEvent[] = [
  "INITIAL_SESSION",
  "SIGNED_IN",
]

export function UserProfileProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<any>(null)
  const [profile, setProfile] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const realtimeTopicSuffix = useId().replace(/:/g, "")
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null)
  const profileRef = useRef<any>(null)
  profileRef.current = profile

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
      setProfile(null)
      setLoading(false)
    }

    async function loadSessionAndProfile() {
      const generation = ++loadGeneration

      if (!profileRef.current) {
        setLoading(true)
      }

      removeProfileChannel()

      // use getSession instead of getUser (prevents lock error)
      const { data } = await supabase.auth.getSession()
      const sessionUser = data?.session?.user

      if (!mounted || generation !== loadGeneration) return

      setUser(sessionUser || null)

      if (!sessionUser) {
        setProfile(null)
        setLoading(false)
        return
      }

      const { data: profileData } = await supabase
        .from("profiles")
        .select("*")
        .eq("id", sessionUser.id)
        .single()

      if (!mounted || generation !== loadGeneration) return

      setProfile(profileData || null)

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
          setProfile(payload.new)
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
    } = supabase.auth.onAuthStateChange((event) => {
      if (!mounted) return

      if (event === "SIGNED_OUT") {
        clearAuthState()
        return
      }

      if (AUTH_SYNC_EVENTS.includes(event)) {
        void loadSessionAndProfile()
      }
    })

    return () => {
      mounted = false
      loadGeneration += 1
      subscription.unsubscribe()
      removeProfileChannel()
    }
  }, [realtimeTopicSuffix])

  const value = useMemo(
    () => ({ user, profile, loading, setProfile }),
    [user, profile, loading]
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
