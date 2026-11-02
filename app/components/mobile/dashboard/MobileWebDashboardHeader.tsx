"use client"

import Link from "next/link"
import { Bell, Calendar } from "lucide-react"
import { useEffect, useState } from "react"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { getDemoUnreadNotificationCount } from "@/lib/demo/demoNotifications"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"
import { fetchSocialNotificationUnreadCount } from "@/lib/socialNotificationUnreadCount"
import {
  getSessionBadges,
  subscribeSessionBootstrapCache,
} from "@/lib/backendV2/sessionBootstrapCache"
import { useUserProfile } from "@/lib/useUserProfile"

export default function MobileWebDashboardHeader() {
  const { user } = useUserProfile()
  const [unread, setUnread] = useState(0)

  useEffect(() => {
    if (!user?.id) {
      setUnread(0)
      return
    }
    if (isDemoModeActive()) {
      setUnread(getDemoUnreadNotificationCount(user.id))
      return
    }

    const applyBadges = () => {
      const badges = getSessionBadges(user.id)
      if (badges && typeof badges.notifications_unread === "number") {
        setUnread(badges.notifications_unread)
        return true
      }
      return false
    }

    if (applyBadges()) {
      return subscribeSessionBootstrapCache(() => {
        applyBadges()
      })
    }

    if (isDemoSupabaseBlocked()) return
    let cancelled = false
    void fetchSocialNotificationUnreadCount(user.id).then((count) => {
      if (!cancelled) setUnread(count)
    })
    return () => {
      cancelled = true
    }
  }, [user?.id])

  return (
    <div className="mb-1 flex h-11 items-center gap-1 px-0.5">
      <Link
        href="/calendar"
        aria-label="Calendar"
        className="inline-flex h-11 w-11 items-center justify-center rounded-full text-white"
      >
        <Calendar className="h-6 w-6" strokeWidth={1.9} aria-hidden />
      </Link>
      <h1 className="min-w-0 flex-1 truncate text-center text-[1.0625rem] font-semibold tracking-tight">
        Dashboard
      </h1>
      <Link
        href="/notifications"
        aria-label={unread > 0 ? `Activity, ${unread} unread` : "Activity"}
        className="relative inline-flex h-11 w-11 items-center justify-center rounded-full text-white"
      >
        <Bell className="h-6 w-6" strokeWidth={1.9} aria-hidden />
        {unread > 0 ? (
          <span
            className="absolute right-1.5 top-1.5 min-w-[16px] rounded-full bg-[#4EC4E0] px-1 text-center text-[10px] font-semibold leading-4 text-[#0B1220]"
            aria-hidden
          >
            {unread > 9 ? "9+" : unread}
          </span>
        ) : null}
      </Link>
    </div>
  )
}
