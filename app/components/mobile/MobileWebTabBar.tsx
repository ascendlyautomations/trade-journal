"use client"

import IntentPrefetchLink from "@/lib/IntentPrefetchLink"
import {
  House,
  Layers,
  MessageCircle,
  Plus,
  User,
} from "lucide-react"
import { usePathname } from "next/navigation"
import { useEffect, useState } from "react"
import { profilePath } from "@/lib/profileRoutes"
import { useUserProfile } from "@/lib/useUserProfile"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
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
import CreateHubMenu from "@/app/components/create/CreateHubMenu"
import {
  resolveMobileWebActiveTab,
  shouldMountMobileWebTabBar,
} from "@/lib/mobileWebTabBar"
import "./mobileWebTabBar.css"

const PROFILE_TAB_AVATAR_PX = 48

/**
 * Phone-only five-tab bar for mobile web. Never mounts on Capacitor or ≥768px.
 */
export default function MobileWebTabBar() {
  const isNativeIos = useIsNativeIos()
  const pathname = usePathname() || "/"
  const { user, profile } = useUserProfile()
  const [unreadMessages, setUnreadMessages] = useState(0)
  const [createOpen, setCreateOpen] = useState(false)

  const profileHref =
    profile != null
      ? profilePath(profile)
      : user?.id
        ? profilePath({ id: user.id })
        : "/profile"
  const profileAvatarUrl = profile?.avatar_url ?? null
  const hasSession = Boolean(user) || pathname.startsWith("/demo")

  useEffect(() => {
    if (isNativeIos || !user?.id || isDemoSupabaseBlocked()) {
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
  }, [isNativeIos, user?.id])

  useEffect(() => {
    if (isNativeIos || !shouldMountMobileWebTabBar(pathname, hasSession)) return
    document.documentElement.classList.add("tt-mobile-web-tabs")
    return () => {
      document.documentElement.classList.remove("tt-mobile-web-tabs")
    }
  }, [isNativeIos, pathname, hasSession])

  if (isNativeIos) return null
  if (!shouldMountMobileWebTabBar(pathname, hasSession)) return null

  const active = resolveMobileWebActiveTab(pathname, profileHref, createOpen)

  const tabClass = (id: typeof active) =>
    `relative flex h-full w-full flex-col items-center justify-center gap-0.5 text-[10px] font-medium ${
      active === id ? "text-info" : "text-chrome-foreground/70"
    }`

  return (
    <>
      <CreateHubMenu
        variant="controller"
        open={createOpen}
        onOpenChange={setCreateOpen}
      />
      <nav
        data-tt-mobile-web-tab-bar
        aria-label="Primary"
        className="md:hidden"
      >
        <ul data-tt-mobile-web-tab-items>
          <li className="min-w-0">
            <IntentPrefetchLink
              href="/dashboard"
              className={tabClass("home")}
              aria-current={active === "home" ? "page" : undefined}
            >
              <House className="h-6 w-6" strokeWidth={active === "home" ? 2.25 : 1.75} aria-hidden />
              <span>Home</span>
            </IntentPrefetchLink>
          </li>
          <li className="min-w-0">
            <IntentPrefetchLink
              href="/feed"
              className={tabClass("feed")}
              aria-current={active === "feed" ? "page" : undefined}
            >
              <Layers className="h-6 w-6" strokeWidth={active === "feed" ? 2.25 : 1.75} aria-hidden />
              <span>Feed</span>
            </IntentPrefetchLink>
          </li>
          <li className="min-w-0">
            <button
              type="button"
              className={tabClass("create")}
              aria-label="Create"
              aria-expanded={createOpen}
              aria-haspopup="dialog"
              onClick={() => setCreateOpen(true)}
            >
              <span
                className={`flex h-7 w-7 items-center justify-center rounded-full ${
                  active === "create"
                    ? "bg-accent text-accent-foreground"
                    : "bg-accent/90 text-accent-foreground"
                }`}
              >
                <Plus className="h-4 w-4" strokeWidth={2.5} aria-hidden />
              </span>
              <span>Create</span>
            </button>
          </li>
          <li className="min-w-0">
            <IntentPrefetchLink
              href="/messages"
              className={tabClass("messages")}
              aria-current={active === "messages" ? "page" : undefined}
            >
              <span className="relative">
                <MessageCircle
                  className="h-6 w-6"
                  strokeWidth={active === "messages" ? 2.25 : 1.75}
                  aria-hidden
                />
                {unreadMessages > 0 ? (
                  <span className="absolute -right-2 -top-1 min-w-[1rem] rounded-full bg-destructive px-1 text-center text-[9px] font-semibold leading-4 text-destructive-foreground tabular-nums">
                    {unreadMessages > 9 ? "9+" : unreadMessages}
                  </span>
                ) : null}
              </span>
              <span>Messages</span>
            </IntentPrefetchLink>
          </li>
          <li className="min-w-0">
            <IntentPrefetchLink
              href={profileHref}
              className={tabClass("profile")}
              aria-current={active === "profile" ? "page" : undefined}
            >
              {profileAvatarUrl ? (
                <span
                  className={`inline-flex rounded-full ${
                    active === "profile"
                      ? "ring-2 ring-accent ring-offset-1 ring-offset-chrome"
                      : "ring-1 ring-chrome-border"
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
                <User
                  className="h-6 w-6"
                  strokeWidth={active === "profile" ? 2.25 : 1.75}
                  aria-hidden
                />
              )}
              <span>Profile</span>
            </IntentPrefetchLink>
          </li>
        </ul>
      </nav>
    </>
  )
}
