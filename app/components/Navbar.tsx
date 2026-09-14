"use client"

import IntentPrefetchLink from "@/lib/IntentPrefetchLink"
import {
  useCallback,
  useEffect,
  useState,
  useRef,
  type MouseEvent as ReactMouseEvent,
} from "react"
import { createPortal } from "react-dom"
import { supabase } from "../../lib/supabaseClient"
import { useRouter, usePathname } from "next/navigation"
import { useUserProfile } from "../../lib/useUserProfile"
import { isProActive } from "../../lib/subscription"
import { getAdminCheckResultForUser } from "../../lib/adminUsers"
import { fetchTotalUnreadMessageCount } from "../../lib/messageUnread"
import { fetchSocialNotificationUnreadCount } from "@/lib/socialNotificationUnreadCount"
import { isBackendV2Enabled } from "@/lib/backendV2/flags.ts"
import { MESSAGING_DM_UNREAD_LOCAL_PATCH } from "@/lib/backendV2/messagingInboxLocalPatch.ts"
import {
  getSessionBadges,
  getSessionIsAdmin,
  patchSessionBadges,
  subscribeSessionBootstrapCache,
} from "@/lib/backendV2/sessionBootstrapCache.ts"
import { profilePath } from "../../lib/profileRoutes"
import { prefetchCriticalAppRoutes } from "../../lib/routePrefetch"
import { scheduleDeferredWork } from "../../lib/scheduleDeferredWork"
import { subscribeNotificationChanges } from "../../lib/notificationRealtime"
import { ProfileAvatarImg } from "./SafeProfileAvatar"
import UserReviewModal from "./beta/UserReviewModal"
import BugReportModal from "./BugReportModal"
import GettingStartedMobileEntry from "./GettingStartedMobileEntry"
import { isDemoUserId } from "@/lib/demo/constants"
import { getDemoUnreadNotificationCount } from "@/lib/demo/demoNotifications"
import { exitDemoMode, isDemoModeActive, disableDemoMode, subscribeDemoModeChanges } from "@/lib/demo/demoMode"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"
import { isStandaloneFlowRoute } from "@/lib/authRoutes"
import { clearSignupFlow } from "@/lib/signupFlow"
import { NAVBAR_BRAND_LINK_CLASS } from "@/lib/navbarBrand"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import {
  DESKTOP_NAV_MORE_DISPLAY_ORDER,
  useDesktopNavOverflow,
  type DesktopNavOverflowId,
} from "@/app/components/useDesktopNavOverflow"
import { useEarlyAccessPromotion } from "@/lib/useEarlyAccessPromotion"
import { isNativeIos } from "@/lib/nativePlatform"
import { NATIVE_IOS_OPEN_APP_MENU_EVENT } from "@/lib/nativeIosAppMenu"
import { useMobileAutoHideNavbar } from "@/app/components/useMobileAutoHideNavbar"
import {
  NAV_ACCOUNT_DROPDOWN_PANEL,
  NAV_CHROME_BAR,
  NAV_CHROME_FIXED_ROOT,
  NAV_CHROME_MOBILE_SCROLL,
  NAV_CTA_PRIMARY,
  NAV_CTA_PRIMARY_MD,
  NAV_DIVIDER,
  NAV_DROPDOWN_PANEL,
  NAV_ITEM_ACTIVE,
  NAV_ITEM_INACTIVE,
  NAV_ITEM_INACTIVE_HOVER_SURFACE,
  NAV_ITEM_MUTED_HOVER_SURFACE,
  NAV_LINK_SECONDARY_HOVER_ACCENT,
  NAV_MENU_ROW,
  NAV_MENU_ROW_DESTRUCTIVE,
  NAV_SECTION_LABEL,
  NAV_SKELETON_PULSE,
  NAV_UNREAD_BADGE,
  NAV_UNREAD_BADGE_ABSOLUTE,
} from "@/lib/navChromeStyles"

export default function Navbar() {
  const pathname = usePathname()
  const isStandalone = isStandaloneFlowRoute(pathname)

  const { user, profile, loading, membershipReconciling } = useUserProfile()
  const { enabled: earlyAccessPromotionEnabled } =
    useEarlyAccessPromotion()
  const profileHref =
    profile != null
      ? profilePath(profile)
      : user?.id
        ? profilePath({ id: user.id })
        : null
  const profileChromePending = !!user && loading && !profile

  const [isOpen, setIsOpen] = useState(false)
  const [openSection, setOpenSection] = useState<string | null>(null)
  const [activeMenu, setActiveMenu] = useState<string | null>(null)
  const [moreSubmenu, setMoreSubmenu] = useState<string | null>(null)
  const [accountMenuOpen, setAccountMenuOpen] = useState(false)
  const [reviewModalOpen, setReviewModalOpen] = useState(false)
  const [bugReportModalOpen, setBugReportModalOpen] = useState(false)
  const [unreadMessagesCount, setUnreadMessagesCount] = useState(0)
  const [unreadCount, setUnreadCount] = useState(0)
  const [isAdmin, setIsAdmin] = useState(false)
  const [hasFetchedNotifications, setHasFetchedNotifications] = useState(false)
  const [hasFetchedMessages, setHasFetchedMessages] = useState(false)
  const [hasFetchedAdmin, setHasFetchedAdmin] = useState(false)
  const [mounted, setMounted] = useState(false)

  const router = useRouter()
  const isHomePage = pathname === "/"
  const isAuthenticatedUser = !!user && !isDemoUserId(user.id)
  const [demoActive, setDemoActive] = useState(false)
  const showMobileNav = !!user || demoActive
  const showReturnToApp = isAuthenticatedUser && isHomePage
  const returnToAppButtonClassName = isHomePage
    ? `inline-flex shrink-0 ${NAV_CTA_PRIMARY_MD}`
    : `hidden shrink-0 md:inline-flex ${NAV_CTA_PRIMARY_MD}`
  const isActive = (path: string) => pathname === path
  const isGroupActive = (paths: string[]) =>
    paths.some((p) => pathname.startsWith(p))

  function handleLogoClick(e: ReactMouseEvent<HTMLAnchorElement>) {
    e.preventDefault()
    setIsOpen(false)
    setActiveMenu(null)
    setMoreSubmenu(null)
    setAccountMenuOpen(false)
    if (isDemoModeActive()) {
      exitDemoMode()
      setUnreadCount(0)
      setUnreadMessagesCount(0)
    }
    router.push("/")
  }

  const handleReturnToApp = useCallback(
    (e: ReactMouseEvent<HTMLButtonElement>) => {
      e.preventDefault()
      setIsOpen(false)
      setActiveMenu(null)
      setMoreSubmenu(null)
      setAccountMenuOpen(false)
      if (isDemoModeActive()) {
        exitDemoMode()
      }
      router.push("/dashboard")
    },
    [router]
  )

  const handleSignOut = useCallback(async () => {
    setIsOpen(false)
    setActiveMenu(null)
    setMoreSubmenu(null)
    setAccountMenuOpen(false)
    disableDemoMode()
    clearSignupFlow()
    try {
      const { unregisterNativeIosPush, setNativeIosBadgeCount } = await import(
        "@/lib/nativeIosPush"
      )
      await unregisterNativeIosPush({ allDevices: false })
      await setNativeIosBadgeCount(0)
    } catch {
      /* ignore — web / plugin unavailable */
    }
    try {
      await supabase.auth.signOut()
    } catch (err) {
      console.error("Sign out failed:", err)
    }
    // replace avoids keeping authenticated pages in history; PublicNavbar must
    // paint immediately for logged-out marketing routes (see shouldShowMarketingNavbar).
    router.replace("/")
  }, [router])

  useEffect(() => {
    const syncDemo = () => setDemoActive(isDemoModeActive())
    syncDemo()
    return subscribeDemoModeChanges(syncDemo)
  }, [])

  useEffect(() => {
    setMounted(true)
  }, [])

  // Capacitor iOS only: open this hamburger as the secondary "More" menu.
  useEffect(() => {
    if (!isNativeIos()) return
    const onOpen = () => {
      setActiveMenu(null)
      setAccountMenuOpen(false)
      setMoreSubmenu(null)
      setIsOpen(true)
    }
    window.addEventListener(NATIVE_IOS_OPEN_APP_MENU_EVENT, onOpen)
    return () => window.removeEventListener(NATIVE_IOS_OPEN_APP_MENU_EVENT, onOpen)
  }, [])

  const mobileMenuOpen = isOpen && showMobileNav
  const forceNavbarVisible =
    mobileMenuOpen ||
    Boolean(activeMenu) ||
    accountMenuOpen ||
    reviewModalOpen ||
    bugReportModalOpen

  const mobileNavbarHidden = useMobileAutoHideNavbar({
    forceVisible: forceNavbarVisible,
    resetKey: pathname,
  })

  useModalScrollLock(mobileMenuOpen)

  const navRef = useRef<HTMLDivElement>(null)
  const badgeText = (count: number) => (count > 99 ? "99+" : String(count))

  // CLOSE ON OUTSIDE CLICK (nav + slide menu + desktop dropdowns)
  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      const el = e.target as HTMLElement | null
      if (!el) return

      if (el.closest("[data-native-ios-bottom-nav]")) {
        return
      }

      if (navRef.current && !navRef.current.contains(el)) {
        setActiveMenu(null)
        setMoreSubmenu(null)
        setAccountMenuOpen(false)
        setIsOpen(false)
        setOpenSection(null)
        return
      }

      if (!el.closest(".profile-menu")) {
        setAccountMenuOpen(false)
      }
    }

    document.addEventListener("mousedown", handleClickOutside)
    return () => document.removeEventListener("mousedown", handleClickOutside)
  }, [])

  const fetchUnreadMessages = useCallback(async () => {
    if (!user?.id) return
    if (isBackendV2Enabled("session")) {
      const badges = getSessionBadges(user.id)
      if (badges) {
        setUnreadMessagesCount(badges.dm_unread)
        return
      }
    }
    const count = await fetchTotalUnreadMessageCount(user.id)
    setUnreadMessagesCount(count)
    if (isBackendV2Enabled("session")) {
      patchSessionBadges(user.id, { dm_unread: count })
    }
  }, [user?.id])

  const fetchUnread = useCallback(async () => {
    if (!user?.id) return

    if (isDemoUserId(user.id)) {
      setUnreadCount(getDemoUnreadNotificationCount(user.id))
      return
    }

    if (isBackendV2Enabled("session")) {
      const badges = getSessionBadges(user.id)
      if (badges) {
        setUnreadCount(badges.notifications_unread)
        return
      }
    }

    const next = await fetchSocialNotificationUnreadCount(user.id)
    setUnreadCount(next)
    if (isBackendV2Enabled("session")) {
      patchSessionBadges(user.id, { notifications_unread: next })
    }
  }, [user?.id])

  useEffect(() => {
    if (!user?.id) return
    const activity = unreadCount ?? 0
    const messages = unreadMessagesCount ?? 0
    void import("@/lib/nativeIosPush").then(({ setNativeIosBadgeCount }) => {
      void setNativeIosBadgeCount(activity + messages)
    })
  }, [user?.id, unreadCount, unreadMessagesCount])

  useEffect(() => {
    if (!user?.id) return
    if (isDemoSupabaseBlocked()) return

    const uid = user.id

    return subscribeNotificationChanges(uid, () => {
      void fetchUnread()
    })
  }, [user?.id, fetchUnread])

  useEffect(() => {
    const onRefresh = () => {
      void fetchUnread()
    }
    window.addEventListener("tj-unread-notifications-refresh", onRefresh)
    window.addEventListener("notification-update", onRefresh)
    return () => {
      window.removeEventListener("tj-unread-notifications-refresh", onRefresh)
      window.removeEventListener("notification-update", onRefresh)
    }
  }, [fetchUnread])

  useEffect(() => {
    const onMessagesRefresh = () => {
      if (isBackendV2Enabled("messageThreads")) return
      void fetchUnreadMessages()
    }
    window.addEventListener("tj-unread-messages-refresh", onMessagesRefresh)
    return () => {
      window.removeEventListener("tj-unread-messages-refresh", onMessagesRefresh)
    }
  }, [fetchUnreadMessages])

  useEffect(() => {
    const onLocalDmUnread = (event: Event) => {
      const detail = (event as CustomEvent<{ userId?: string; dmUnread?: number }>)
        .detail
      if (!user?.id || detail?.userId !== user.id) return
      if (typeof detail.dmUnread !== "number") return
      setUnreadMessagesCount(detail.dmUnread)
      if (isBackendV2Enabled("session")) {
        patchSessionBadges(user.id, { dm_unread: detail.dmUnread })
      }
    }
    window.addEventListener(MESSAGING_DM_UNREAD_LOCAL_PATCH, onLocalDmUnread)
    return () => {
      window.removeEventListener(MESSAGING_DM_UNREAD_LOCAL_PATCH, onLocalDmUnread)
    }
  }, [user?.id])

  useEffect(() => {
    if (!user?.id || loading || membershipReconciling) return

    let cancelled = false

    const applyBadgesFromSession = () => {
      if (!isBackendV2Enabled("session") || !user?.id) return false
      const badges = getSessionBadges(user.id)
      if (!badges) return false
      setUnreadCount(badges.notifications_unread)
      setUnreadMessagesCount(badges.dm_unread)
      setHasFetchedNotifications(true)
      setHasFetchedMessages(true)
      return true
    }

    // Session RPC already owns initial badge counts — do not re-fetch on paint.
    if (applyBadgesFromSession()) {
      return
    }

    // Bootstrap may still be in-flight while loading=false from cache paint.
    // Session ON: wait for cache only — never REST-duplicate badge stack.
    if (isBackendV2Enabled("session")) {
      const unsub = subscribeSessionBootstrapCache(() => {
        if (!cancelled) applyBadgesFromSession()
      })
      return () => {
        cancelled = true
        unsub()
      }
    }

    scheduleDeferredWork(() => {
      void (async () => {
        await fetchUnread()
        if (!cancelled) setHasFetchedNotifications(true)
      })()

      void (async () => {
        await fetchUnreadMessages()
        if (!cancelled) setHasFetchedMessages(true)
      })()
    })

    return () => {
      cancelled = true
    }
  }, [user?.id, loading, membershipReconciling, fetchUnread, fetchUnreadMessages])

  useEffect(() => {
    if (!user?.id || loading || membershipReconciling) return
    prefetchCriticalAppRoutes(router, pathname ?? undefined)
  }, [user?.id, loading, membershipReconciling, router, pathname])

  useEffect(() => {
    if (!user?.id || loading || membershipReconciling) {
      if (!user?.id) {
        setIsAdmin(false)
        setHasFetchedAdmin(false)
      }
      return
    }

    if (isDemoUserId(user.id)) {
      setIsAdmin(false)
      setHasFetchedAdmin(true)
      return
    }

    let cancelled = false

    const applyAdminFromSession = () => {
      if (!isBackendV2Enabled("session") || !user?.id) return false
      const fromSession = getSessionIsAdmin(user.id)
      if (fromSession === null) return false
      setIsAdmin(fromSession)
      setHasFetchedAdmin(true)
      return true
    }

    // Session owns is_admin — do not REST-duplicate admin_users on paint.
    if (applyAdminFromSession()) {
      return
    }

    if (isBackendV2Enabled("session")) {
      const unsub = subscribeSessionBootstrapCache(() => {
        if (!cancelled) applyAdminFromSession()
      })
      return () => {
        cancelled = true
        unsub()
      }
    }

    scheduleDeferredWork(() => {
      void (async () => {
        const check = await getAdminCheckResultForUser(user.id, user.email)
        if (process.env.NODE_ENV !== "production") {
          console.debug("[admin-check][navbar] resolved", {
            userId: check.userId,
            email: check.email,
            adminRow: check.row,
            error: check.error,
            isAdmin: check.isAdmin,
          })
        }
        if (!cancelled) {
          setIsAdmin(check.isAdmin)
          setHasFetchedAdmin(true)
        }
      })()
    })

    return () => {
      cancelled = true
    }
  }, [user?.id, user?.email, loading, membershipReconciling])

  const toggleSection = (section: string) => {
    setOpenSection((prev) => (prev === section ? null : section))
  }

  function toggleMenu(menu: string) {
    setAccountMenuOpen(false)
    setMoreSubmenu(null)
    setActiveMenu(activeMenu === menu ? null : menu)
  }

  function toggleMoreSubmenu(submenu: string) {
    setMoreSubmenu(moreSubmenu === submenu ? null : submenu)
  }

  const handleToggleNotifications = async () => {
    if (hasFetchedNotifications) return
    if (user?.id && isBackendV2Enabled("session")) {
      const badges = getSessionBadges(user.id)
      if (badges) {
        setUnreadCount(badges.notifications_unread)
        setHasFetchedNotifications(true)
        return
      }
    }
    await fetchUnread()
    setHasFetchedNotifications(true)
  }

  const handleToggleMessages = async () => {
    if (hasFetchedMessages) return
    if (user?.id && isBackendV2Enabled("session")) {
      const badges = getSessionBadges(user.id)
      if (badges) {
        setUnreadMessagesCount(badges.dm_unread)
        setHasFetchedMessages(true)
        return
      }
    }
    await fetchUnreadMessages()
    setHasFetchedMessages(true)
  }

  const handleToggleAccountMenu = async () => {
    setActiveMenu(null)
    setMoreSubmenu(null)
    setAccountMenuOpen((open) => !open)

    if (!hasFetchedAdmin && user?.id) {
      if (isBackendV2Enabled("session")) {
        const fromSession = getSessionIsAdmin(user.id)
        if (fromSession !== null) {
          setIsAdmin(fromSession)
          setHasFetchedAdmin(true)
          return
        }
      }
      const check = await getAdminCheckResultForUser(user.id, user.email)
      if (process.env.NODE_ENV !== "production") {
        console.debug("[admin-check][navbar] resolved", {
          userId: check.userId,
          email: check.email,
          adminRow: check.row,
          error: check.error,
          isAdmin: check.isAdmin,
        })
      }
      setIsAdmin(check.isAdmin)
      setHasFetchedAdmin(true)
    }
  }

  useEffect(() => {
    setIsOpen(false)
    setOpenSection(null)
    setActiveMenu(null)
    setMoreSubmenu(null)
    setAccountMenuOpen(false)
  }, [pathname])

  const analyticsLinks: {
    label: string
    href: string
    proOnly?: boolean
    beta?: boolean
  }[] = [
    { label: "Calendar", href: "/calendar" },
    { label: "Prop Firm Mode", href: "/analytics/propfirm", proOnly: true },
    { label: "AI Analyst", href: "/analyst", proOnly: true },
    { label: "Achievements", href: "/achievements" },
    { label: "Backtest Lab", href: "/backtest", proOnly: true },
    { label: "Streaks", href: "/streaks" },
  ]

  const betaBadge = (
    <span className="shrink-0 text-[10px] px-2 py-[2px] rounded bg-yellow-500/20 text-yellow-300 border border-yellow-400/30">
      BETA
    </span>
  )

  const proBadge = (
    <span className="shrink-0 text-[10px] font-medium tracking-wide text-amber-200/80">
      🔒 PRO
    </span>
  )

  const closeMobile = () => {
    setIsOpen(false)
    setOpenSection(null)
  }

  function analyticsLinkLabel(item: { label: string; beta?: boolean }) {
    return (
      <div className="flex min-w-0 flex-1 items-center gap-2">
        <span className="truncate">{item.label}</span>
        {item.beta ? betaBadge : null}
      </div>
    )
  }

  type AnalyticsLinkItem = (typeof analyticsLinks)[number]
  const isProUser = isProActive(profile)

  function analyticsLinkClassName(
    item: AnalyticsLinkItem,
    layout: "desktop" | "mobile"
  ) {
    const base =
      layout === "desktop"
        ? "flex w-full items-center justify-between gap-2 rounded px-3 py-2"
        : "flex w-full items-center justify-between gap-2 rounded-lg px-3 py-1.5"
    const state = isActive(item.href)
      ? NAV_ITEM_ACTIVE
      : item.proOnly && !isProUser
        ? NAV_ITEM_MUTED_HOVER_SURFACE
        : NAV_ITEM_INACTIVE_HOVER_SURFACE
    return `${base} ${state}`
  }

  function renderAnalyticsNavLink(
    item: AnalyticsLinkItem,
    layout: "desktop" | "mobile"
  ) {
    return (
      <IntentPrefetchLink
        key={item.label}
        href={item.href}
        className={analyticsLinkClassName(item, layout)}
        onClick={layout === "mobile" ? closeMobile : undefined}
      >
        {analyticsLinkLabel(item)}
        {item.proOnly && !isProUser ? proBadge : null}
      </IntentPrefetchLink>
    )
  }

  function renderAnalyticsDropdown(layout: "desktop" | "mobile") {
    if (isProUser) {
      return analyticsLinks.map((item) => renderAnalyticsNavLink(item, layout))
    }

    const freeLinks = analyticsLinks.filter((item) => !item.proOnly)
    const proLinks = analyticsLinks.filter((item) => item.proOnly)

    return (
      <>
        {freeLinks.map((item) => renderAnalyticsNavLink(item, layout))}
        {proLinks.length > 0 ? (
          <>
            <div
              className={
                layout === "desktop"
                  ? "mx-2 my-1 border-t border-border px-1 pt-2 pb-1"
                  : "mx-1 my-1 border-t border-border px-2 pt-2 pb-1"
              }
              role="presentation"
            >
              <span className={NAV_SECTION_LABEL}>
                TradeTraxs Pro
              </span>
            </div>
            {proLinks.map((item) => renderAnalyticsNavLink(item, layout))}
          </>
        ) : null}
      </>
    )
  }

  const communityLinks: { label: string; href: string }[] = [
    { label: "Trade Rooms", href: "/community" },
    { label: "Leaderboard", href: "/leaderboard" },
    { label: "Explore", href: "/explore" },
  ]

  const affiliateReferralCode =
    profile?.referral_code != null ? String(profile.referral_code).trim() : ""
  const hasAffiliateAccess = affiliateReferralCode.length > 0
  const affiliateMenuItem = hasAffiliateAccess
    ? { label: "Affiliate Dashboard", href: "/affiliate/dashboard" }
    : { label: "Become an Affiliate", href: "/affiliate" }

  const notificationBellControl = (
    iconClassName: string,
    wrapperClassName = "",
    badgeClassName = NAV_UNREAD_BADGE_ABSOLUTE
  ) => (
    <div
      className={`relative shrink-0 cursor-pointer ${wrapperClassName}`.trim()}
      role="button"
      tabIndex={0}
      aria-label="Notifications"
      onClick={() => {
        void import("@/lib/nativeHaptics").then(({ hapticLight }) => {
          hapticLight("notifications")
        })
        void handleToggleNotifications()
        setAccountMenuOpen(false)
        setActiveMenu(null)
        setMoreSubmenu(null)
        router.push("/notifications")
      }}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault()
          void import("@/lib/nativeHaptics").then(({ hapticLight }) => {
            hapticLight("notifications")
          })
          void handleToggleNotifications()
          setAccountMenuOpen(false)
          setActiveMenu(null)
          setMoreSubmenu(null)
          router.push("/notifications")
        }
      }}
    >
      <div className={`${iconClassName} text-white`} aria-hidden>
        🔔
      </div>
      {unreadCount > 0 ? (
        <span className={badgeClassName}>
          {badgeText(unreadCount)}
        </span>
      ) : null}
    </div>
  )

  const betaEligible = Boolean(profile?.is_beta_tester)
  const desktopNavEnabled = !isHomePage && !!user
  const {
    containerRef: desktopNavContainerRef,
    moreMeasureRef,
    setPinnedRef,
    setItemMeasureRef,
    overflowIds,
    isOverflowing,
  } = useDesktopNavOverflow({
    enabled: desktopNavEnabled,
    measureKey: [
      unreadMessagesCount,
      betaEligible ? "beta" : "no-beta",
      profileHref ?? "no-profile",
    ].join("|"),
    betaEligible,
  })

  const overflowDisplayIds = DESKTOP_NAV_MORE_DISPLAY_ORDER.filter((id) =>
    overflowIds.includes(id)
  )

  const moreMenuActive =
    overflowIds.some((id) => {
      if (id === "messages") return isActive("/messages")
      if (id === "analytics") {
        return isGroupActive([
          "/analytics",
          "/backtest",
          "/calendar",
          "/streaks",
          "/achievements",
          "/analyst",
        ])
      }
      if (id === "community") {
        return isGroupActive([
          "/community",
          "/trade-rooms",
          "/leaderboard",
          "/explore",
        ])
      }
      if (id === "beta") return isActive("/beta")
      return false
    }) || activeMenu === "more"

  const navTriggerClass = (active: boolean) =>
    `shrink-0 rounded px-2 py-1 transition ${
      active
        ? NAV_ITEM_ACTIVE
        : NAV_ITEM_INACTIVE
    }`

  const renderMoreOverflowItem = (id: DesktopNavOverflowId) => {
    if (id === "messages") {
      return (
        <IntentPrefetchLink
          key="messages"
          href="/messages"
          className={`flex items-center justify-between gap-2 rounded px-3 py-2 ${
            isActive("/messages")
              ? NAV_ITEM_ACTIVE
              : NAV_ITEM_INACTIVE_HOVER_SURFACE
          }`}
          onClick={() => {
            void handleToggleMessages()
            setActiveMenu(null)
            setMoreSubmenu(null)
          }}
        >
          <span>Messages</span>
          {unreadMessagesCount > 0 ? (
            <span className={NAV_UNREAD_BADGE}>
              {unreadMessagesCount > 9 ? "9+" : unreadMessagesCount}
            </span>
          ) : null}
        </IntentPrefetchLink>
      )
    }

    if (id === "beta") {
      return (
        <IntentPrefetchLink
          key="beta"
          href="/beta"
          className={`block rounded px-3 py-2 ${
            isActive("/beta")
              ? NAV_ITEM_ACTIVE
              : NAV_ITEM_INACTIVE_HOVER_SURFACE
          }`}
          onClick={() => {
            setActiveMenu(null)
            setMoreSubmenu(null)
          }}
        >
          Beta
        </IntentPrefetchLink>
      )
    }

    if (id === "analytics") {
      return (
        <div key="analytics">
          <button
            type="button"
            onClick={() => toggleMoreSubmenu("analytics")}
            className={`flex w-full items-center justify-between rounded px-3 py-2 text-left ${
              isGroupActive([
                "/analytics",
                "/backtest",
                "/calendar",
                "/streaks",
                "/achievements",
                "/analyst",
              ]) || moreSubmenu === "analytics"
                ? NAV_ITEM_ACTIVE
                : NAV_ITEM_INACTIVE_HOVER_SURFACE
            }`}
          >
            <span>Analytics</span>
            <span aria-hidden>{moreSubmenu === "analytics" ? "▾" : "▸"}</span>
          </button>
          {moreSubmenu === "analytics" ? (
            <div className="border-t border-border pb-1 pl-2">
              {renderAnalyticsDropdown("desktop")}
            </div>
          ) : null}
        </div>
      )
    }

    if (id === "community") {
      return (
        <div key="community">
          <button
            type="button"
            onClick={() => toggleMoreSubmenu("community")}
            className={`flex w-full items-center justify-between rounded px-3 py-2 text-left ${
              isGroupActive([
                "/community",
                "/trade-rooms",
                "/leaderboard",
                "/explore",
              ]) || moreSubmenu === "community"
                ? NAV_ITEM_ACTIVE
                : NAV_ITEM_INACTIVE_HOVER_SURFACE
            }`}
          >
            <span>Community</span>
            <span aria-hidden>{moreSubmenu === "community" ? "▾" : "▸"}</span>
          </button>
          {moreSubmenu === "community" ? (
            <div className="border-t border-border pb-1 pl-2">
              {communityLinks.map((item) => (
                <IntentPrefetchLink
                  key={item.href}
                  href={item.href}
                  className={`block rounded px-3 py-2 ${
                    isActive(item.href)
                      ? NAV_ITEM_ACTIVE
                      : NAV_ITEM_INACTIVE_HOVER_SURFACE
                  }`}
                  onClick={() => {
                    setActiveMenu(null)
                    setMoreSubmenu(null)
                  }}
                >
                  {item.label}
                </IntentPrefetchLink>
              ))}
            </div>
          ) : null}
        </div>
      )
    }

    return null
  }

  if (isStandalone) return null

  const navbar = (
    <div
      ref={navRef}
      className={`${NAV_CHROME_FIXED_ROOT} transition-transform duration-200 ease-out will-change-transform ${
        mobileNavbarHidden ? "max-md:-translate-y-full md:translate-y-0" : "translate-y-0"
      } ${
        mobileMenuOpen
          ? "flex max-h-[100dvh] flex-col overflow-hidden md:block md:max-h-none md:overflow-visible"
          : "overflow-visible"
      }`}
    >
      <div className={NAV_CHROME_BAR}>
        <div className="flex h-full w-full items-center gap-2 px-4 md:gap-3 md:px-6">
        {/* LEFT */}
        <div className="flex min-w-0 flex-1 items-center gap-3">
          <IntentPrefetchLink
            href="/"
            onClick={handleLogoClick}
            className={NAVBAR_BRAND_LINK_CLASS}
          >
            TradeTraxs
          </IntentPrefetchLink>

          {!user && !isHomePage ? (
            <IntentPrefetchLink href="/faq" className={`hidden md:inline text-sm transition ${NAV_LINK_SECONDARY_HOVER_ACCENT}`}>
              FAQ
            </IntentPrefetchLink>
          ) : null}

          {isHomePage && user ? (
            <div className="hidden min-w-0 items-center gap-3 text-sm md:flex">
              <IntentPrefetchLink
                href="/faq"
                className={`shrink-0 rounded px-2 py-1 transition ${
                  isActive("/faq")
                    ? NAV_ITEM_ACTIVE
                    : NAV_ITEM_INACTIVE
                }`}
              >
                FAQ
              </IntentPrefetchLink>
              {!earlyAccessPromotionEnabled ? (
                <IntentPrefetchLink
                  href="/pricing"
                  className={`shrink-0 rounded px-2 py-1 transition ${
                    isActive("/pricing")
                      ? NAV_ITEM_ACTIVE
                      : NAV_ITEM_INACTIVE
                  }`}
                >
                  Pricing
                </IntentPrefetchLink>
              ) : null}
            </div>
          ) : null}

          {!isHomePage && user ? (
            <div
              ref={desktopNavContainerRef}
              className="relative hidden min-w-0 flex-1 items-center gap-3 text-sm md:flex"
            >
              {/* Off-screen measurers — keep widths in sync without affecting layout */}
              <div
                aria-hidden
                className="pointer-events-none fixed left-[-9999px] top-0 flex items-center gap-3 text-sm"
              >
                <button
                  ref={moreMeasureRef}
                  type="button"
                  tabIndex={-1}
                  className="shrink-0 rounded px-2 py-1"
                >
                  More ▾
                </button>
                <span
                  ref={setItemMeasureRef("messages")}
                  className="inline-flex shrink-0 items-center gap-2 rounded px-2 py-1"
                >
                  Messages
                  {unreadMessagesCount > 0 ? (
                    <span className={NAV_UNREAD_BADGE}>
                      {unreadMessagesCount > 9 ? "9+" : unreadMessagesCount}
                    </span>
                  ) : null}
                </span>
                <span
                  ref={setItemMeasureRef("analytics")}
                  className="shrink-0 rounded px-2 py-1"
                >
                  Analytics ▾
                </span>
                <span
                  ref={setItemMeasureRef("community")}
                  className="shrink-0 rounded px-2 py-1"
                >
                  Community ▾
                </span>
                {betaEligible ? (
                  <span
                    ref={setItemMeasureRef("beta")}
                    className="shrink-0 rounded border px-3 py-1.5 text-sm font-medium border-yellow-400/30"
                  >
                    Beta
                  </span>
                ) : null}
              </div>

              <span ref={setPinnedRef("add-trade")} className="shrink-0">
                <IntentPrefetchLink
                  href="/app"
                  className={navTriggerClass(isActive("/app"))}
                >
                  Add Trade
                </IntentPrefetchLink>
              </span>
              <span ref={setPinnedRef("dashboard")} className="shrink-0">
                <IntentPrefetchLink
                  href="/dashboard"
                  className={navTriggerClass(isActive("/dashboard"))}
                >
                  Dashboard
                </IntentPrefetchLink>
              </span>
              <span ref={setPinnedRef("trades")} className="shrink-0">
                <IntentPrefetchLink
                  href="/trades"
                  className={navTriggerClass(isActive("/trades"))}
                >
                  Trades
                </IntentPrefetchLink>
              </span>
              <span ref={setPinnedRef("feed")} className="shrink-0">
                <IntentPrefetchLink
                  href="/feed"
                  className={navTriggerClass(isActive("/feed"))}
                >
                  Feed
                </IntentPrefetchLink>
              </span>
              <span ref={setPinnedRef("profile")} className="shrink-0">
                {profileHref ? (
                  <IntentPrefetchLink
                    href={profileHref}
                    className={navTriggerClass(isGroupActive(["/profile"]))}
                  >
                    Profile
                  </IntentPrefetchLink>
                ) : (
                  <span className="shrink-0 rounded px-2 py-1 text-muted-foreground">
                    Profile
                  </span>
                )}
              </span>

              {!isOverflowing("messages") ? (
                <IntentPrefetchLink
                  href="/messages"
                  className={`inline-flex shrink-0 items-center gap-2 rounded px-2 py-1 transition ${
                    isActive("/messages")
                      ? NAV_ITEM_ACTIVE
                      : NAV_ITEM_INACTIVE
                  }`}
                  onClick={() => {
                    void import("@/lib/nativeHaptics").then(({ hapticLight }) => {
                      hapticLight("open-messages")
                    })
                    void handleToggleMessages()
                  }}
                >
                  Messages
                  {unreadMessagesCount > 0 ? (
                    <span className={NAV_UNREAD_BADGE}>
                      {unreadMessagesCount > 9 ? "9+" : unreadMessagesCount}
                    </span>
                  ) : null}
                </IntentPrefetchLink>
              ) : null}

              {!isOverflowing("analytics") ? (
                <div className="relative shrink-0">
                  <button
                    type="button"
                    onClick={() => toggleMenu("analytics")}
                    className={navTriggerClass(
                      isGroupActive([
                        "/analytics",
                        "/backtest",
                        "/calendar",
                        "/streaks",
                        "/achievements",
                        "/analyst",
                      ])
                    )}
                  >
                    Analytics ▾
                  </button>
                  {activeMenu === "analytics" ? (
                    <div className={NAV_DROPDOWN_PANEL}>
                      {renderAnalyticsDropdown("desktop")}
                    </div>
                  ) : null}
                </div>
              ) : null}

              {!isOverflowing("community") ? (
                <div className="relative shrink-0">
                  <button
                    type="button"
                    onClick={() => toggleMenu("community")}
                    className={navTriggerClass(
                      isGroupActive([
                        "/community",
                        "/trade-rooms",
                        "/leaderboard",
                        "/explore",
                      ])
                    )}
                  >
                    Community ▾
                  </button>
                  {activeMenu === "community" ? (
                    <div className={NAV_DROPDOWN_PANEL}>
                      {communityLinks.map((item) => (
                        <IntentPrefetchLink
                          key={item.href}
                          href={item.href}
                          className={`block rounded px-3 py-2 ${
                            isActive(item.href)
                              ? NAV_ITEM_ACTIVE
                              : NAV_ITEM_INACTIVE_HOVER_SURFACE
                          }`}
                        >
                          {item.label}
                        </IntentPrefetchLink>
                      ))}
                    </div>
                  ) : null}
                </div>
              ) : null}

              {overflowDisplayIds.length > 0 ? (
                <div className="relative shrink-0">
                  <button
                    type="button"
                    onClick={() => toggleMenu("more")}
                    aria-expanded={activeMenu === "more"}
                    aria-haspopup="menu"
                    className={navTriggerClass(moreMenuActive)}
                  >
                    More ▾
                  </button>
                  {activeMenu === "more" ? (
                    <div className={NAV_DROPDOWN_PANEL}>
                      {overflowDisplayIds.map((id) =>
                        renderMoreOverflowItem(id)
                      )}
                    </div>
                  ) : null}
                </div>
              ) : null}
            </div>
          ) : null}
        </div>

        {/* RIGHT */}
        <div className="ml-auto flex shrink-0 items-center justify-end gap-2 md:gap-4">
        {showReturnToApp ? (
          <button
            type="button"
            onClick={handleReturnToApp}
            className={returnToAppButtonClassName}
          >
            Return to App
          </button>
        ) : null}
        {showMobileNav ? (
          <>
            {user && isAdmin ? (
              <IntentPrefetchLink
                href="/admin"
                className={`md:hidden shrink-0 rounded-lg px-2.5 py-1.5 text-xs font-medium transition ${
                  isGroupActive(["/admin"])
                    ? NAV_ITEM_ACTIVE
                    : `${NAV_LINK_SECONDARY_HOVER_ACCENT}`
                }`}
              >
                Admin
              </IntentPrefetchLink>
            ) : null}

            <div className="flex shrink-0 items-center gap-2.5 md:hidden">
              {!isHomePage && user
                ? notificationBellControl(
                    "text-lg leading-none",
                    "inline-flex items-center justify-center px-1 py-1",
                    `absolute -right-0.5 -top-0.5 min-w-[1rem] px-1 py-px text-center text-[10px] leading-tight ${NAV_UNREAD_BADGE}`
                  )
                : null}
              <button
                type="button"
                className="shrink-0 px-1 py-1 text-2xl leading-none text-chrome-foreground"
                aria-expanded={isOpen}
                aria-label={isOpen ? "Close menu" : "Open menu"}
                onClick={() => {
                  setActiveMenu(null)
                  if (isOpen) {
                    setOpenSection(null)
                    setIsOpen(false)
                  } else {
                    void import("@/lib/nativeHaptics").then(({ hapticLight }) => {
                      hapticLight("menu")
                    })
                    setIsOpen(true)
                  }
                }}
              >
                ☰
              </button>
            </div>

            {!isHomePage && user ? (
              <div className="hidden items-center gap-3 md:flex">
                {isAdmin ? (
                  <IntentPrefetchLink href="/admin" className="text-sm hover:text-nav-link-hover">
                    Admin
                  </IntentPrefetchLink>
                ) : null}

                {notificationBellControl("text-xl", "mr-2")}

                <GettingStartedMobileEntry placement="desktop-nav" />

                {profile?.is_beta_tester && !isOverflowing("beta") ? (
                  <IntentPrefetchLink
                    href="/beta"
                    className={`shrink-0 rounded border px-3 py-1.5 text-sm font-medium transition ${
                      isActive("/beta")
                        ? "border-yellow-400/50 bg-yellow-500/30 text-yellow-200"
                        : "border-yellow-400/30 bg-yellow-500/20 text-yellow-300 hover:bg-yellow-500/30"
                    }`}
                  >
                    Beta
                  </IntentPrefetchLink>
                ) : null}

                <div className="profile-menu relative">
                  <button
                    type="button"
                    onClick={() => {
                      void handleToggleAccountMenu()
                    }}
                    className="flex items-center gap-2 rounded border px-3 py-1"
                  >
                    {!profileChromePending ? (
                      <ProfileAvatarImg
                        src={profile?.avatar_url}
                        className="h-8 w-8"
                      />
                    ) : (
                      <div className={`h-8 w-8 ${NAV_SKELETON_PULSE}`} aria-hidden />
                    )}
                    {!profileChromePending ? (
                      <span>{profile?.username ?? user?.email?.split("@")[0]}</span>
                    ) : (
                      <div className={`h-4 w-20 ${NAV_SKELETON_PULSE}`} />
                    )}
                  </button>

                  {accountMenuOpen ? (
                    <div className={NAV_ACCOUNT_DROPDOWN_PANEL}>
                      <button
                        type="button"
                        onClick={() => {
                          setAccountMenuOpen(false)
                          router.push("/settings#account")
                        }}
                        className={NAV_MENU_ROW}
                      >
                        Settings
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setAccountMenuOpen(false)
                          router.push(affiliateMenuItem.href)
                        }}
                        className={NAV_MENU_ROW}
                      >
                        {affiliateMenuItem.label}
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setAccountMenuOpen(false)
                          router.push("/help")
                        }}
                        className={NAV_MENU_ROW}
                      >
                        Help Center
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setAccountMenuOpen(false)
                          setReviewModalOpen(true)
                        }}
                        className={NAV_MENU_ROW}
                      >
                        Leave a Review
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          void handleSignOut()
                        }}
                        className={NAV_MENU_ROW_DESTRUCTIVE}
                      >
                        Sign Out
                      </button>
                    </div>
                  ) : null}
                </div>
              </div>
            ) : null}
          </>
        ) : isHomePage ? (
          loading ? null : (
          <IntentPrefetchLink
            href="/login"
            className={`shrink-0 px-4 py-2 ${NAV_CTA_PRIMARY}`}
          >
            Login
          </IntentPrefetchLink>
          )
        ) : loading ? null : (
          <div className="flex shrink-0 items-center gap-3">
            <IntentPrefetchLink href="/faq" className={`md:hidden text-sm transition ${NAV_LINK_SECONDARY_HOVER_ACCENT}`}>
              FAQ
            </IntentPrefetchLink>
            <button type="button" onClick={() => router.push("/login")} className="border px-4 py-2 rounded shrink-0">
              Login
            </button>
          </div>
        )}
        </div>
        </div>
      </div>

      {mobileMenuOpen ? (
        <div className={`${NAV_CHROME_MOBILE_SCROLL} [webkit-overflow-scrolling:touch]`}>
          <div className="flex w-full flex-col gap-1 px-4 pb-[calc(0.75rem+var(--safe-area-bottom)+var(--app-tab-bar-height))] pt-1.5 text-sm text-chrome-foreground md:px-6">
          {isNativeIos() ? (
            <>
              {/* Native iOS: primary tabs live in the bottom bar — this is More. */}
              {showReturnToApp ? (
                <button
                  type="button"
                  onClick={handleReturnToApp}
                  className={`rounded-lg px-3 py-1.5 font-medium ${NAV_CTA_PRIMARY}`}
                >
                  Return to App
                </button>
              ) : null}
              {user ? <GettingStartedMobileEntry placement="menu" /> : null}

              <p className="px-3 pb-0.5 pt-1 text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
                Trading
              </p>
              <IntentPrefetchLink
                href="/calendar"
                className={`rounded-lg px-3 py-1.5 transition ${
                  isActive("/calendar")
                    ? NAV_ITEM_ACTIVE
                    : NAV_ITEM_INACTIVE
                }`}
                onClick={closeMobile}
              >
                Calendar
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/trades"
                className={`rounded-lg px-3 py-1.5 transition ${
                  isActive("/trades")
                    ? NAV_ITEM_ACTIVE
                    : NAV_ITEM_INACTIVE
                }`}
                onClick={closeMobile}
              >
                Trades
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/backtest"
                className={`flex items-center justify-between gap-2 rounded-lg px-3 py-1.5 transition ${
                  isActive("/backtest")
                    ? NAV_ITEM_ACTIVE
                    : isProUser
                      ? NAV_ITEM_INACTIVE
                      : NAV_ITEM_MUTED_HOVER_SURFACE
                }`}
                onClick={closeMobile}
              >
                <span>Backtest Lab</span>
                {!isProUser ? proBadge : null}
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/analyst"
                className={`flex items-center justify-between gap-2 rounded-lg px-3 py-1.5 transition ${
                  isActive("/analyst")
                    ? NAV_ITEM_ACTIVE
                    : isProUser
                      ? NAV_ITEM_INACTIVE
                      : NAV_ITEM_MUTED_HOVER_SURFACE
                }`}
                onClick={closeMobile}
              >
                <span>AI Trade Analyst</span>
                {!isProUser ? proBadge : null}
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/import"
                className={`rounded-lg px-3 py-1.5 transition ${
                  isActive("/import")
                    ? NAV_ITEM_ACTIVE
                    : NAV_ITEM_INACTIVE
                }`}
                onClick={closeMobile}
              >
                Import CSV
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/analytics/propfirm"
                className={`flex items-center justify-between gap-2 rounded-lg px-3 py-1.5 transition ${
                  isActive("/analytics/propfirm")
                    ? NAV_ITEM_ACTIVE
                    : isProUser
                      ? NAV_ITEM_INACTIVE
                      : NAV_ITEM_MUTED_HOVER_SURFACE
                }`}
                onClick={closeMobile}
              >
                <span>Prop Firm Mode</span>
                {!isProUser ? proBadge : null}
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/achievements"
                className={`rounded-lg px-3 py-1.5 transition ${
                  isActive("/achievements")
                    ? NAV_ITEM_ACTIVE
                    : NAV_ITEM_INACTIVE
                }`}
                onClick={closeMobile}
              >
                Achievements
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/streaks"
                className={`rounded-lg px-3 py-1.5 transition ${
                  isActive("/streaks")
                    ? NAV_ITEM_ACTIVE
                    : NAV_ITEM_INACTIVE
                }`}
                onClick={closeMobile}
              >
                Streaks
              </IntentPrefetchLink>

              <p className="px-3 pb-0.5 pt-2.5 text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
                Community
              </p>
              <IntentPrefetchLink
                href="/explore"
                className={`rounded-lg px-3 py-1.5 transition ${
                  isActive("/explore")
                    ? NAV_ITEM_ACTIVE
                    : NAV_ITEM_INACTIVE
                }`}
                onClick={closeMobile}
              >
                Explore
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/community"
                className={`rounded-lg px-3 py-1.5 transition ${
                  isActive("/community") || pathname.startsWith("/room/")
                    ? NAV_ITEM_ACTIVE
                    : NAV_ITEM_INACTIVE
                }`}
                onClick={closeMobile}
              >
                Trade Rooms
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/leaderboard"
                className={`rounded-lg px-3 py-1.5 transition ${
                  isActive("/leaderboard")
                    ? NAV_ITEM_ACTIVE
                    : NAV_ITEM_INACTIVE
                }`}
                onClick={closeMobile}
              >
                Leaderboard
              </IntentPrefetchLink>

              <p className="px-3 pb-0.5 pt-2.5 text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
                Account
              </p>
              <button
                type="button"
                className={`flex w-full items-center justify-between rounded-lg px-3 py-1.5 text-left transition ${NAV_ITEM_INACTIVE}`}
                onClick={() => {
                  void handleToggleNotifications()
                  closeMobile()
                  router.push("/notifications")
                }}
              >
                <span>Notifications</span>
                {unreadCount > 0 ? (
                  <span className={`px-2 py-0.5 text-xs tabular-nums ${NAV_UNREAD_BADGE}`}>
                    {badgeText(unreadCount)}
                  </span>
                ) : null}
              </button>
              <IntentPrefetchLink
                href="/settings#subscription"
                className={`rounded-lg px-3 py-1.5 transition ${NAV_ITEM_INACTIVE}`}
                onClick={closeMobile}
              >
                Billing / Subscription
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/referrals"
                className={`rounded-lg px-3 py-1.5 transition ${
                  isActive("/referrals")
                    ? NAV_ITEM_ACTIVE
                    : NAV_ITEM_INACTIVE
                }`}
                onClick={closeMobile}
              >
                Referrals
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/settings#account"
                className={`rounded-lg px-3 py-1.5 transition ${NAV_ITEM_INACTIVE}`}
                onClick={closeMobile}
              >
                Settings
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href={affiliateMenuItem.href}
                className={`rounded-lg px-3 py-1.5 transition ${
                  isGroupActive([
                    "/affiliate",
                    "/affiliate/dashboard",
                    "/affiliate/payout-setup",
                    "/payouts",
                  ])
                    ? NAV_ITEM_ACTIVE
                    : NAV_ITEM_INACTIVE
                }`}
                onClick={closeMobile}
              >
                {affiliateMenuItem.label}
              </IntentPrefetchLink>

              <p className="px-3 pb-0.5 pt-2.5 text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
                Support
              </p>
              <button
                type="button"
                className={`rounded-lg px-3 py-1.5 text-left transition ${NAV_ITEM_INACTIVE}`}
                onClick={() => {
                  closeMobile()
                  setReviewModalOpen(true)
                }}
              >
                Leave a Review
              </button>
              <button
                type="button"
                className={`rounded-lg px-3 py-1.5 text-left transition ${NAV_ITEM_INACTIVE}`}
                onClick={() => {
                  closeMobile()
                  setBugReportModalOpen(true)
                }}
              >
                Report Bug
              </button>
              <IntentPrefetchLink
                href="/feature-requests"
                className={`rounded-lg px-3 py-1.5 transition ${
                  isActive("/feature-requests")
                    ? NAV_ITEM_ACTIVE
                    : NAV_ITEM_INACTIVE
                }`}
                onClick={closeMobile}
              >
                Feature Requests
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/help"
                className={`rounded-lg px-3 py-1.5 transition ${NAV_ITEM_INACTIVE}`}
                onClick={closeMobile}
              >
                Help / Support
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/privacy"
                className={`rounded-lg px-3 py-1.5 transition ${NAV_ITEM_INACTIVE}`}
                onClick={closeMobile}
              >
                Privacy Policy
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/terms"
                className={`rounded-lg px-3 py-1.5 transition ${NAV_ITEM_INACTIVE}`}
                onClick={closeMobile}
              >
                Terms of Service
              </IntentPrefetchLink>

              {(profile?.is_beta_tester || isAdmin) ? (
                <>
                  <p className="px-3 pb-0.5 pt-2.5 text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
                    Developer
                  </p>
                  {profile?.is_beta_tester ? (
                    <IntentPrefetchLink
                      href="/beta"
                      className={`flex items-center gap-2 rounded-lg px-3 py-1.5 transition ${
                        isActive("/beta")
                          ? "border border-yellow-400/40 bg-yellow-500/25 text-yellow-200"
                          : "border border-yellow-400/25 bg-yellow-500/15 text-yellow-300 hover:bg-yellow-500/25"
                      }`}
                      onClick={closeMobile}
                    >
                      <span>Beta Hub</span>
                      {betaBadge}
                    </IntentPrefetchLink>
                  ) : null}
                  {isAdmin ? (
                    <IntentPrefetchLink
                      href="/admin"
                      className="rounded-lg px-3 py-1.5 text-chrome-foreground hover:text-nav-link-hover"
                      onClick={closeMobile}
                    >
                      Admin
                    </IntentPrefetchLink>
                  ) : null}
                </>
              ) : null}

              <div className="mt-1 border-t border-border pt-1.5">
                <button
                  type="button"
                  className="w-full rounded-lg px-3 py-1.5 text-left text-sm text-red-400 hover:text-red-300"
                  onClick={() => {
                    void handleSignOut()
                  }}
                >
                  Sign Out
                </button>
              </div>
            </>
          ) : (
            <>
          {showReturnToApp ? (
            <button
              type="button"
              onClick={handleReturnToApp}
              className={`rounded-lg px-3 py-1.5 font-medium ${NAV_CTA_PRIMARY}`}
            >
              Return to App
            </button>
          ) : null}
          {user ? <GettingStartedMobileEntry placement="menu" /> : null}
          <IntentPrefetchLink
            href="/app"
            className={`rounded-lg px-3 py-1.5 transition ${
              isActive("/app")
                ? NAV_ITEM_ACTIVE
                : NAV_ITEM_INACTIVE
            }`}
            onClick={closeMobile}
          >
            Add Trade
          </IntentPrefetchLink>

          <IntentPrefetchLink
            href="/dashboard"
            className={`rounded-lg px-3 py-1.5 transition ${
              isActive("/dashboard")
                ? NAV_ITEM_ACTIVE
                : NAV_ITEM_INACTIVE
            }`}
            onClick={closeMobile}
          >
            Dashboard
          </IntentPrefetchLink>

          <IntentPrefetchLink
            href="/trades"
            className={`rounded-lg px-3 py-1.5 transition ${
              isActive("/trades")
                ? NAV_ITEM_ACTIVE
                : NAV_ITEM_INACTIVE
            }`}
            onClick={closeMobile}
          >
            Trades
          </IntentPrefetchLink>

          <IntentPrefetchLink
            href="/feed"
            className={`rounded-lg px-3 py-1.5 transition ${
              isActive("/feed")
                ? NAV_ITEM_ACTIVE
                : NAV_ITEM_INACTIVE
            }`}
            onClick={closeMobile}
          >
            Feed
          </IntentPrefetchLink>

          {profileHref ? (
            <IntentPrefetchLink
              href={profileHref}
              className={`rounded-lg px-3 py-1.5 transition ${
                isGroupActive(["/profile"])
                  ? NAV_ITEM_ACTIVE
                  : NAV_ITEM_INACTIVE
              }`}
              onClick={() => {
                void import("@/lib/nativeHaptics").then(({ hapticLight }) => {
                  hapticLight("open-profile")
                })
                closeMobile()
              }}
            >
              Profile
            </IntentPrefetchLink>
          ) : (
            <span className="rounded-lg px-3 py-1.5 text-muted-foreground">Profile</span>
          )}

          <IntentPrefetchLink
            href="/messages"
            className={`flex items-center justify-between rounded-lg px-3 py-1.5 transition ${
              isActive("/messages")
                ? NAV_ITEM_ACTIVE
                : NAV_ITEM_INACTIVE
            }`}
            onClick={() => {
              void import("@/lib/nativeHaptics").then(({ hapticLight }) => {
                hapticLight("open-messages")
              })
              void handleToggleMessages()
              closeMobile()
            }}
          >
            <span>Messages</span>
            {unreadMessagesCount > 0 ? (
              <span className={`text-xs px-2 py-0.5 rounded-full tabular-nums ${NAV_UNREAD_BADGE}`}>
                {unreadMessagesCount > 9 ? "9+" : unreadMessagesCount}
              </span>
            ) : null}
          </IntentPrefetchLink>

          <div>
            <button
              type="button"
              className={`flex w-full items-center justify-between rounded-lg px-3 py-1.5 transition ${
                isGroupActive([
                  "/analytics",
                  "/backtest",
                  "/calendar",
                  "/streaks",
                  "/achievements",
                  "/analyst",
                ])
                  ? NAV_ITEM_ACTIVE
                  : NAV_ITEM_INACTIVE
              }`}
              onClick={() => toggleSection("analytics")}
            >
              <span>Analytics</span>
              <span className="text-muted-foreground tabular-nums">{openSection === "analytics" ? "−" : "+"}</span>
            </button>
            {openSection === "analytics" ? (
              <div className="mt-1 space-y-0.5 pl-3 text-sm">
                {renderAnalyticsDropdown("mobile")}
              </div>
            ) : null}
          </div>

          <div>
            <button
              type="button"
              className={`flex w-full items-center justify-between rounded-lg px-3 py-1.5 transition ${
                isGroupActive(["/community", "/trade-rooms", "/leaderboard", "/explore"])
                  ? NAV_ITEM_ACTIVE
                  : NAV_ITEM_INACTIVE
              }`}
              onClick={() => toggleSection("community")}
            >
              <span>Community</span>
              <span className="text-muted-foreground tabular-nums">{openSection === "community" ? "−" : "+"}</span>
            </button>
            {openSection === "community" ? (
              <div className="mt-1 space-y-0.5 pl-3 text-sm">
                {communityLinks.map((item) => (
                  <IntentPrefetchLink
                    key={item.href}
                    href={item.href}
                    className={`block rounded-lg px-3 py-1.5 ${
                      isActive(item.href)
                        ? NAV_ITEM_ACTIVE
                        : NAV_ITEM_INACTIVE_HOVER_SURFACE
                    }`}
                    onClick={closeMobile}
                  >
                    {item.label}
                  </IntentPrefetchLink>
                ))}
              </div>
            ) : null}
          </div>

          {profile?.is_beta_tester ? (
            <IntentPrefetchLink
              href="/beta"
              className={`flex items-center gap-2 rounded-lg px-3 py-1.5 transition ${
                isActive("/beta")
                  ? "border border-yellow-400/40 bg-yellow-500/25 text-yellow-200"
                  : "border border-yellow-400/25 bg-yellow-500/15 text-yellow-300 hover:bg-yellow-500/25"
              }`}
              onClick={closeMobile}
            >
              <span>Beta Hub</span>
              {betaBadge}
            </IntentPrefetchLink>
          ) : null}

          <div className="flex flex-col gap-1 border-t border-border pt-1.5">
            {isAdmin ? (
              <IntentPrefetchLink
                href="/admin"
                className="rounded-lg px-3 py-1.5 text-chrome-foreground hover:text-nav-link-hover"
                onClick={closeMobile}
              >
                Admin
              </IntentPrefetchLink>
            ) : null}

            <IntentPrefetchLink
              href="/settings#account"
              className="rounded-lg px-3 py-1.5 text-chrome-foreground hover:text-nav-link-hover"
              onClick={closeMobile}
            >
              Settings
            </IntentPrefetchLink>
            <IntentPrefetchLink
              href={affiliateMenuItem.href}
              className={`rounded-lg px-3 py-1.5 transition ${
                isGroupActive([
                  "/affiliate",
                  "/affiliate/dashboard",
                  "/affiliate/payout-setup",
                  "/payouts",
                ])
                  ? NAV_ITEM_ACTIVE
                  : "text-chrome-foreground hover:text-nav-link-hover"
              }`}
              onClick={closeMobile}
            >
              {affiliateMenuItem.label}
            </IntentPrefetchLink>
            <IntentPrefetchLink
              href="/help"
              className="rounded-lg px-3 py-1.5 text-chrome-foreground hover:text-nav-link-hover"
              onClick={closeMobile}
            >
              Help Center
            </IntentPrefetchLink>
            <button
              type="button"
              className="rounded-lg px-3 py-1.5 text-left text-chrome-foreground hover:text-nav-link-hover"
              onClick={() => {
                closeMobile()
                setReviewModalOpen(true)
              }}
            >
              Leave a Review
            </button>

            <button
              type="button"
              className="flex w-full items-center justify-between rounded-lg px-3 py-1.5 text-left text-chrome-foreground hover:text-nav-link-hover"
              onClick={() => {
                void handleToggleNotifications()
                closeMobile()
                router.push("/notifications")
              }}
            >
              <span>Notifications</span>
              {unreadCount > 0 ? (
                <span className={`text-xs px-2 py-0.5 rounded-full tabular-nums ${NAV_UNREAD_BADGE}`}>
                  {badgeText(unreadCount)}
                </span>
              ) : null}
            </button>

            <button
              type="button"
              className="w-full rounded-lg px-3 py-1.5 text-left text-sm text-red-400 hover:text-red-300"
              onClick={() => {
                void handleSignOut()
              }}
            >
              Sign Out
            </button>
          </div>
            </>
          )}
          </div>
        </div>
      ) : null}

      <UserReviewModal
        open={reviewModalOpen}
        userId={user?.id ?? null}
        onClose={() => setReviewModalOpen(false)}
      />
      <BugReportModal
        open={bugReportModalOpen}
        onClose={() => setBugReportModalOpen(false)}
      />
    </div>
  )

  if (!mounted) return null

  return createPortal(navbar, document.body)
}