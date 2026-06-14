"use client"

import { useEffect } from "react"
import * as Sentry from "@sentry/nextjs"
import { useUserProfile } from "@/lib/useUserProfile"

/** Attach Supabase user id to Sentry events when a session exists. */
export default function SentryIdentifyUser() {
  const { user } = useUserProfile()

  useEffect(() => {
    const userId = user?.id
    if (typeof userId === "string" && userId.trim()) {
      Sentry.setUser({ id: userId })
      return
    }
    Sentry.setUser(null)
  }, [user?.id])

  return null
}
