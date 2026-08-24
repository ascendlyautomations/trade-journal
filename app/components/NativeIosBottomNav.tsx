"use client"

import IntentPrefetchLink from "@/lib/IntentPrefetchLink"
import {
  LayoutDashboard,
  MessageCircle,
  Newspaper,
  Plus,
  User,
} from "lucide-react"
import { usePathname } from "next/navigation"
import { useEffect, useState } from "react"
import { profilePath } from "@/lib/profileRoutes"
import { useUserProfile } from "@/lib/useUserProfile"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import { hapticLight } from "@/lib/nativeHaptics"
import { fetchTotalUnreadMessageCount } from "@/lib/messageUnread"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import { isBackendV2Enabled } from "@/lib/backendV2/flags.ts"
import { MESSAGING_DM_UNREAD_LOCAL_PATCH } from "@/lib/backendV2/messagingInboxLocalPatch.ts"
import {
  getSessionBadges,
  patchSessionBadges,
  subscribeSessionBootstrapCache,
} from "@/lib/backendV2/sessionBootstrapCache.ts"

type RouteTab = {
  id: "dashboard" | "feed" | "add" | "messages" | "profile"
  label: string
  href: string
  Icon: typeof LayoutDashboard
  emphasize?: boolean
  isActive: (pathname: string, profileHref: string | null) => boolean
}

/** 24px tab glyph @2× retina — matches Lucide h-6 siblings. */
const PROFILE_TAB_AVATAR_PX = 48

/**
 * Fixed iOS Capacitor tab bar. Web / Android / Safari never mount this.
 * Geometry lives in globals.css (.tt-ios-tab-bar) so safe-area and item-row
 * height share one source of truth with --app-tab-bar-offset.
 */
export default function NativeIosBottomNav() {
  const enabled = useIsNativeIos()
  const pathname = usePathname() || "/"
  const { user, profile } = useUserProfile()
  const [unreadMessages, setUnreadMessages] = useState(0)

  const profileHref =
    profile != null
      ? profilePath(profile)
      : user?.id
        ? profilePath({ id: user.id })
        : "/profile"
  const profileAvatarUrl = profile?.avatar_url ?? null

  useEffect(() => {
    if (!enabled || !user?.id || isDemoSupabaseBlocked()) {
      setUnreadMessages(0)
      return
    }
    let cancelled = false

    const applyFromSession = () => {
      if (!isBackendV2Enabled("session")) return false
      const badges = getSessionBadges(user.id)
      if (!badges) return false
      setUnreadMessages(badges.dm_unread)
      return true
    }

    if (applyFromSession()) {
      const onRefresh = () => {
        if (isBackendV2Enabled("messageThreads")) return
        void fetchTotalUnreadMessageCount(user.id).then((count) => {
          if (cancelled) return
          setUnreadMessages(count)
          patchSessionBadges(user.id, { dm_unread: count })
        })
      }
      window.addEventListener("tj-unread-messages-refresh", onRefresh)
      return () => {
        cancelled = true
        window.removeEventListener("tj-unread-messages-refresh", onRefresh)
      }
    }

    const unsub = isBackendV2Enabled("session")
      ? subscribeSessionBootstrapCache(() => {
          if (!cancelled) applyFromSession()
        })
      : () => {}

    const refresh = () => {
      void fetchTotalUnreadMessageCount(user.id).then((count) => {
        if (cancelled) return
        setUnreadMessages(count)
        if (isBackendV2Enabled("session")) {
          patchSessionBadges(user.id, { dm_unread: count })
        }
      })
    }
    if (!isBackendV2Enabled("session")) {
      refresh()
    }
    const onRefresh = () => {
      if (isBackendV2Enabled("messageThreads")) return
      refresh()
    }
    window.addEventListener("tj-unread-messages-refresh", onRefresh)
    const onLocalPatch = (event: Event) => {
      const detail = (event as CustomEvent<{ userId?: string; dmUnread?: number }>)
        .detail
      if (!user?.id || detail?.userId !== user.id) return
      if (typeof detail.dmUnread !== "number") return
      setUnreadMessages(detail.dmUnread)
      if (isBackendV2Enabled("session")) {
        patchSessionBadges(user.id, { dm_unread: detail.dmUnread })
      }
    }
    window.addEventListener(MESSAGING_DM_UNREAD_LOCAL_PATCH, onLocalPatch)
    return () => {
      cancelled = true
      unsub()
      window.removeEventListener("tj-unread-messages-refresh", onRefresh)
      window.removeEventListener(MESSAGING_DM_UNREAD_LOCAL_PATCH, onLocalPatch)
    }
  }, [enabled, user?.id])

  if (!enabled) return null
  // Same mount gate as the app Navbar — no tab bar on marketing/auth chrome.
  if (!user && !pathname.startsWith("/demo")) return null

  const tabs: RouteTab[] = [
    {
      id: "dashboard",
      label: "Dashboard",
      href: "/dashboard",
      Icon: LayoutDashboard,
      isActive: (p) => p === "/dashboard" || p.startsWith("/dashboard/"),
    },
    {
      id: "feed",
      label: "Feed",
      href: "/feed",
      Icon: Newspaper,
      isActive: (p) => p === "/feed" || p.startsWith("/feed/"),
    },
    {
      id: "add",
      label: "Add Trade",
      href: "/app",
      Icon: Plus,
      emphasize: true,
      isActive: (p) =>
        p === "/app" || p.startsWith("/app/") || p === "/input-trade",
    },
    {
      id: "messages",
      label: "Messages",
      href: "/messages",
      Icon: MessageCircle,
      isActive: (p) => p === "/messages" || p.startsWith("/messages/"),
    },
    {
      id: "profile",
      label: "Profile",
      href: profileHref,
      Icon: User,
      isActive: (p, href) => {
        if (!href) return false
        if (p === href) return true
        return p.startsWith(`${href}/`)
      },
    },
  ]

  return (
    <nav
      data-native-ios-bottom-nav
      aria-label="Primary"
      className="tt-ios-tab-bar"
    >
      <ul className="tt-ios-tab-bar__items">
        {tabs.map((tab) => {
          const active = tab.isActive(pathname, profileHref)
          const showMsgBadge = tab.id === "messages" && unreadMessages > 0

          if (tab.emphasize) {
            return (
              <li key={tab.id} className="min-w-0">
                <IntentPrefetchLink
                  href={tab.href}
                  onClick={() => hapticLight(`tab-${tab.id}`)}
                  className="flex h-full w-full flex-col items-center justify-center gap-0.5"
                  aria-current={active ? "page" : undefined}
                  aria-label={tab.label}
                >
                  <span
                    className={`flex h-7 w-7 items-center justify-center rounded-full transition-colors ${
                      active
                        ? "bg-blue-500 text-white shadow-[0_0_0_2px_rgba(59,130,246,0.35)]"
                        : "bg-blue-600/90 text-white active:bg-blue-500"
                    }`}
                  >
                    <tab.Icon className="h-4 w-4" strokeWidth={2.5} aria-hidden />
                  </span>
                  <span
                    className={`text-[9px] font-semibold leading-none ${
                      active ? "text-blue-300" : "text-gray-300"
                    }`}
                  >
                    {tab.label}
                  </span>
                </IntentPrefetchLink>
              </li>
            )
          }

          return (
            <li key={tab.id} className="min-w-0">
              <IntentPrefetchLink
                href={tab.href}
                onClick={() => hapticLight(`tab-${tab.id}`)}
                className={`relative flex h-full w-full flex-col items-center justify-center gap-0.5 text-[10px] font-medium transition-colors ${
                  active ? "text-blue-300" : "text-gray-400 active:text-white"
                }`}
                aria-current={active ? "page" : undefined}
              >
                <span className="relative">
                  {tab.id === "profile" ? (
                    profileAvatarUrl ? (
                      <span
                        className={`inline-flex rounded-full ${
                          active
                            ? "ring-2 ring-blue-400 ring-offset-1 ring-offset-[#0b1f3a]"
                            : "ring-1 ring-white/20"
                        }`}
                      >
                        <ProfileAvatarImg
                          src={profileAvatarUrl}
                          alt=""
                          className="h-6 w-6"
                          displaySizePx={PROFILE_TAB_AVATAR_PX}
                          priority
                        />
                      </span>
                    ) : (
                      <tab.Icon
                        className="h-6 w-6 shrink-0"
                        strokeWidth={active ? 2.25 : 1.75}
                        aria-hidden
                      />
                    )
                  ) : (
                    <tab.Icon
                      className="h-6 w-6 shrink-0"
                      strokeWidth={active ? 2.25 : 1.75}
                      aria-hidden
                    />
                  )}
                  {showMsgBadge ? (
                    <span className="absolute -right-2 -top-1 min-w-[1rem] rounded-full bg-red-500 px-1 text-center text-[9px] font-semibold leading-4 text-white tabular-nums">
                      {unreadMessages > 9 ? "9+" : unreadMessages}
                    </span>
                  ) : null}
                </span>
                <span className="leading-none">{tab.label}</span>
                {active ? (
                  <span
                    className="absolute top-0 h-0.5 w-5 rounded-full bg-blue-400"
                    aria-hidden
                  />
                ) : null}
              </IntentPrefetchLink>
            </li>
          )
        })}
      </ul>
    </nav>
  )
}
