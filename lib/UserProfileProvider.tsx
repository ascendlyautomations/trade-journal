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
import { supabase } from "./supabaseClient"

type UserProfileContextValue = {
  user: any
  profile: any
  loading: boolean
  setProfile: Dispatch<SetStateAction<any>>
}

const UserProfileContext = createContext<UserProfileContextValue | null>(null)

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

    async function init() {
      if (!profileRef.current) {
        setLoading(true)
      }

      if (channelRef.current) {
        void supabase.removeChannel(channelRef.current)
        channelRef.current = null
      }

      // ✅ FIX: use getSession instead of getUser (prevents lock error)
      const { data } = await supabase.auth.getSession()
      const sessionUser = data?.session?.user

      if (!mounted) return

      setUser(sessionUser || null)

      if (!sessionUser) {
        if (mounted) setLoading(false)
        return
      }

      const { data: profileData } = await supabase
        .from("profiles")
        .select("*")
        .eq("id", sessionUser.id)
        .single()

      if (!mounted) return

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
          if (!mounted) return
          setProfile(payload.new)
        }
      )

      if (!mounted) {
        void supabase.removeChannel(ch)
        channelRef.current = null
        return
      }

      ch.subscribe()

      if (mounted) setLoading(false)
    }

    void init()

    return () => {
      mounted = false
      const ch = channelRef.current
      channelRef.current = null
      if (ch) {
        void supabase.removeChannel(ch)
      }
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
