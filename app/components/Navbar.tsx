"use client"

import Link from "next/link"
import { useCallback, useEffect, useState, useRef, type MouseEvent } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter, usePathname } from "next/navigation"
import { useUserProfile } from "../../lib/useUserProfile"
import { isProActive } from "../../lib/subscription"
import { getCurrentAdminCheckResult } from "../../lib/adminUsers"
import { fetchTotalUnreadMessageCount } from "../../lib/messageUnread"
import { NOTIFICATION_INBOX_TYPES } from "../../lib/notificationEngagementTypes"
import { profilePath } from "../../lib/profileRoutes"
import { prefetchAppRoutes } from "../../lib/routePrefetch"
import { ProfileAvatarImg } from "./SafeProfileAvatar"
import BugReportModal from "./BugReportModal"
import GettingStartedMobileEntry from "./GettingStartedMobileEntry"
import { isDemoUserId } from "@/lib/demo/constants"
import { getDemoUnreadNotificationCount } from "@/lib/demo/demoNotifications"
import { exitDemoMode, isDemoModeActive, subscribeDemoModeChanges } from "@/lib/demo/demoMode"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"

export default function Navbar() {
  const { user, profile, loading } = useUserProfile()
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
  const [accountMenuOpen, setAccountMenuOpen] = useState(false)
  const [bugReportOpen, setBugReportOpen] = useState(false)
  const [unreadMessagesCount, setUnreadMessagesCount] = useState(0)
  const [unreadCount, setUnreadCount] = useState(0)
  const [isAdmin, setIsAdmin] = useState(false)
  const [hasFetchedNotifications, setHasFetchedNotifications] = useState(false)
  const [hasFetchedMessages, setHasFetchedMessages] = useState(false)
  const [hasFetchedAdmin, setHasFetchedAdmin] = useState(false)

  const router = useRouter()
  const pathname = usePathname()
  const isHomePage = pathname === "/"
  const isPreviewAppRoute = pathname === "/app"
  const [demoActive, setDemoActive] = useState(false)
  const showReturnToApp =
    !!user && (isHomePage || isPreviewAppRoute || demoActive)
  const isActive = (path: string) => pathname === path
  const isGroupActive = (paths: string[]) =>
    paths.some((p) => pathname.startsWith(p))

  function handleLogoClick(e: MouseEvent<HTMLAnchorElement>) {
    if (!isDemoModeActive()) return
    e.preventDefault()
    exitDemoMode()
    setIsOpen(false)
    setActiveMenu(null)
    setAccountMenuOpen(false)
    setUnreadCount(0)
    setUnreadMessagesCount(0)
    router.push("/")
  }

  const handleReturnToApp = useCallback(
    (e: MouseEvent<HTMLButtonElement>) => {
      e.preventDefault()
      setIsOpen(false)
      setActiveMenu(null)
      setAccountMenuOpen(false)
      if (isDemoModeActive()) {
        exitDemoMode()
      }
      router.push("/dashboard")
    },
    [router]
  )

  useEffect(() => {
    const syncDemo = () => setDemoActive(isDemoModeActive())
    syncDemo()
    return subscribeDemoModeChanges(syncDemo)
  }, [])

  const navRef = useRef<HTMLDivElement>(null)
  const badgeText = (count: number) => (count > 99 ? "99+" : String(count))

  // CLOSE ON OUTSIDE CLICK (nav + slide menu + desktop dropdowns)
  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      const el = e.target as HTMLElement | null
      if (!el) return

      if (navRef.current && !navRef.current.contains(el)) {
        setActiveMenu(null)
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
    const count = await fetchTotalUnreadMessageCount(user.id)
    setUnreadMessagesCount(count)
  }, [user])

  const fetchUnread = useCallback(async () => {
    if (!user?.id) return

    if (isDemoUserId(user.id)) {
      setUnreadCount(getDemoUnreadNotificationCount(user.id))
      return
    }

    const { count, error } = await supabase
      .from("notifications")
      .select("*", { count: "exact", head: true })
      .eq("user_id", user.id)
      .eq("read", false)
      .in("type", [...NOTIFICATION_INBOX_TYPES])

    if (error) {
      console.error("[navbar] unread notifications fetch failed", {
        query:
          "notifications select count where user_id = currentUser and read = false (like, comment, room_join, follow)",
        userId: user.id,
        message: error.message,
        details: error.details,
        hint: error.hint,
        code: error.code,
      })
      return
    }

    setUnreadCount(count ?? 0)
  }, [user])

  useEffect(() => {
    if (!user?.id) return
    if (isDemoSupabaseBlocked()) return

    const uid = user.id

    const channel = supabase.channel(`notif-${uid}`)

    channel.on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table: "notifications",
        filter: `user_id=eq.${uid}`,
      },
      (payload: { new?: { user_id?: string }; old?: { user_id?: string } }) => {
        const row = payload.new ?? payload.old
        if (row?.user_id === uid) {
          void fetchUnread()
        }
      }
    )

    channel.subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [user, fetchUnread])

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
      void fetchUnreadMessages()
    }
    window.addEventListener("tj-unread-messages-refresh", onMessagesRefresh)
    return () => {
      window.removeEventListener("tj-unread-messages-refresh", onMessagesRefresh)
    }
  }, [fetchUnreadMessages])

  useEffect(() => {
    if (!user?.id) return

    let cancelled = false

    void (async () => {
      await fetchUnread()
      if (!cancelled) setHasFetchedNotifications(true)
    })()

    void (async () => {
      await fetchUnreadMessages()
      if (!cancelled) setHasFetchedMessages(true)
    })()

    return () => {
      cancelled = true
    }
  }, [user?.id, fetchUnread, fetchUnreadMessages])

  useEffect(() => {
    if (!user?.id) return
    prefetchAppRoutes(router)
  }, [user?.id, router])

  useEffect(() => {
    if (!user?.id) {
      setIsAdmin(false)
      setHasFetchedAdmin(false)
      return
    }

    if (isDemoUserId(user.id)) {
      setIsAdmin(false)
      setHasFetchedAdmin(true)
      return
    }

    let cancelled = false

    void (async () => {
      const check = await getCurrentAdminCheckResult()
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

    return () => {
      cancelled = true
    }
  }, [user?.id])

  const toggleSection = (section: string) => {
    setOpenSection((prev) => (prev === section ? null : section))
  }

  function toggleMenu(menu: string) {
    setAccountMenuOpen(false)
    setActiveMenu(activeMenu === menu ? null : menu)
  }

  const handleToggleNotifications = async () => {
    if (!hasFetchedNotifications) {
      await fetchUnread()
      setHasFetchedNotifications(true)
    }
  }

  const handleToggleMessages = async () => {
    if (!hasFetchedMessages) {
      await fetchUnreadMessages()
      setHasFetchedMessages(true)
    }
  }

  const handleToggleAccountMenu = async () => {
    setActiveMenu(null)
    setAccountMenuOpen((open) => !open)

    if (!hasFetchedAdmin && user?.id) {
      const check = await getCurrentAdminCheckResult()
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
    setAccountMenuOpen(false)
  }, [pathname])

  const analyticsLinks: {
    label: string
    href: string
    proOnly?: boolean
    beta?: boolean
  }[] = [
    { label: "Calendar", href: "/calendar" },
    { label: "Achievements", href: "/achievements" },
    { label: "Prop Firm Mode", href: "/analytics/propfirm", proOnly: true },
    { label: "AI Analyst", href: "/analyst", proOnly: true },
    { label: "Backtest Lab", href: "/backtest", proOnly: true },
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

  function analyticsLinkLabel(item: { label: string; beta?: boolean }) {
    return (
      <div className="flex min-w-0 flex-1 items-center gap-2">
        <span className="truncate">{item.label}</span>
        {item.beta ? betaBadge : null}
      </div>
    )
  }

  const communityLinks: { label: string; href: string }[] = [
    { label: "Feed", href: "/feed" },
    { label: "Trade Rooms", href: "/trade-rooms" },
    { label: "Leaderboard", href: "/leaderboard" },
    { label: "Explore", href: "/explore" },
  ]

  const affiliateReferralCode =
    profile?.referral_code != null ? String(profile.referral_code).trim() : ""
  const hasAffiliateAccess = affiliateReferralCode.length > 0

  const affiliateLinks: { label: string; href: string }[] = hasAffiliateAccess
    ? [
        { label: "Affiliate Dashboard", href: "/affiliate" },
        { label: "Affiliate Payouts", href: "/payouts" },
      ]
    : [{ label: "Become an Affiliate", href: "/affiliate?apply=true" }]

  const closeMobile = () => {
    setIsOpen(false)
    setOpenSection(null)
  }

  const notificationBellControl = (
    iconClassName: string,
    wrapperClassName = "",
    badgeClassName = "absolute -right-2 -top-1 min-w-[1.25rem] rounded-full bg-red-500 px-1.5 py-0.5 text-center text-xs tabular-nums text-white"
  ) => (
    <div
      className={`relative shrink-0 cursor-pointer ${wrapperClassName}`.trim()}
      role="button"
      tabIndex={0}
      aria-label="Notifications"
      onClick={() => {
        void handleToggleNotifications()
        setAccountMenuOpen(false)
        setActiveMenu(null)
        router.push("/notifications")
      }}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault()
          void handleToggleNotifications()
          setAccountMenuOpen(false)
          setActiveMenu(null)
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

  return (
    <div ref={navRef} className="fixed top-0 left-0 z-[9999] w-full overflow-visible text-gray-100">
      <div className="flex h-16 w-full shrink-0 items-center border-b border-white/5 bg-[#0b1f3a]">
        <div className="flex h-full w-full items-center justify-between px-4 md:px-6">
        {/* LEFT */}
        <div className="flex min-w-0 items-center gap-3">
          <Link
            href="/"
            onClick={handleLogoClick}
            className="font-bold text-xl shrink-0 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent"
          >
            TradeTraxs
          </Link>

          {!user && !isHomePage ? (
            <Link href="/faq" className="hidden md:inline text-sm text-gray-200 hover:text-blue-400 transition">
              FAQ
            </Link>
          ) : null}

          {isHomePage && user ? (
            <div className="hidden min-w-0 items-center gap-3 text-sm md:flex">
              <Link
                href="/faq"
                className={`shrink-0 rounded px-2 py-1 transition ${
                  isActive("/faq")
                    ? "bg-blue-500/20 text-blue-300"
                    : "text-gray-300 hover:text-white"
                }`}
              >
                FAQ
              </Link>
              <Link
                href="/pricing"
                className={`shrink-0 rounded px-2 py-1 transition ${
                  isActive("/pricing")
                    ? "bg-blue-500/20 text-blue-300"
                    : "text-gray-300 hover:text-white"
                }`}
              >
                Pricing
              </Link>
            </div>
          ) : null}

          {!isHomePage && user ? (
            <div className="hidden min-w-0 items-center gap-3 text-sm md:flex">
              <Link
                href="/app"
                className={`shrink-0 rounded px-2 py-1 transition ${
                  isActive("/app")
                    ? "bg-blue-500/20 text-blue-300"
                    : "text-gray-300 hover:text-white"
                }`}
              >
                Input Trade
              </Link>
              <Link
                href="/dashboard"
                className={`shrink-0 rounded px-2 py-1 transition ${
                  isActive("/dashboard")
                    ? "bg-blue-500/20 text-blue-300"
                    : "text-gray-300 hover:text-white"
                }`}
              >
                Dashboard
              </Link>
              <Link
                href="/trades"
                className={`shrink-0 rounded px-2 py-1 transition ${
                  isActive("/trades")
                    ? "bg-blue-500/20 text-blue-300"
                    : "text-gray-300 hover:text-white"
                }`}
              >
                Trades
              </Link>
              {profileHref ? (
                <Link
                  href={profileHref}
                  className={`shrink-0 rounded px-2 py-1 transition ${
                    isGroupActive(["/profile"])
                      ? "bg-blue-500/20 text-blue-300"
                      : "text-gray-300 hover:text-white"
                  }`}
                >
                  Profile
                </Link>
              ) : (
                <span className="shrink-0 rounded px-2 py-1 text-gray-500">
                  Profile
                </span>
              )}
              <Link
                href="/messages"
                className={`inline-flex shrink-0 items-center gap-2 rounded px-2 py-1 transition ${
                  isActive("/messages")
                    ? "bg-blue-500/20 text-blue-300"
                    : "text-gray-300 hover:text-white"
                }`}
                onClick={() => {
                  void handleToggleMessages()
                }}
              >
                Messages
                {unreadMessagesCount > 0 ? (
                  <span className="rounded-full bg-red-500 px-1.5 py-0.5 text-xs tabular-nums text-white">
                    {unreadMessagesCount > 9 ? "9+" : unreadMessagesCount}
                  </span>
                ) : null}
              </Link>

              <div className="relative">
                <button
                  type="button"
                  onClick={() => toggleMenu("analytics")}
                  className={`shrink-0 rounded px-2 py-1 transition ${
                    isGroupActive([
                      "/analytics",
                      "/backtest",
                      "/calendar",
                      "/achievements",
                      "/analyst",
                    ])
                      ? "bg-blue-500/20 text-blue-300"
                      : "text-gray-300 hover:text-white"
                  }`}
                >
                  Analytics ▾
                </button>
                {activeMenu === "analytics" ? (
                  <div className="absolute top-full z-[9999] mt-2 w-56 rounded border border-white/10 bg-[#1e293b] shadow-lg">
                    {analyticsLinks.map((item) => (
                        <Link
                          key={item.href}
                          href={item.href}
                          className={`flex w-full items-center justify-between gap-2 rounded px-3 py-2 ${
                            isActive(item.href)
                              ? "bg-blue-500/20 text-blue-300"
                              : item.proOnly && !isProActive(profile)
                                ? "text-gray-400 hover:bg-white/10"
                                : "text-gray-300 hover:bg-white/10"
                          }`}
                        >
                          {analyticsLinkLabel(item)}
                          {item.proOnly && !isProActive(profile) ? proBadge : null}
                        </Link>
                      ))}
                  </div>
                ) : null}
              </div>

              <div className="relative">
                <button
                  type="button"
                  onClick={() => toggleMenu("community")}
                  className={`shrink-0 rounded px-2 py-1 transition ${
                    isGroupActive([
                      "/community",
                      "/feed",
                      "/trade-rooms",
                      "/leaderboard",
                      "/explore",
                    ])
                      ? "bg-blue-500/20 text-blue-300"
                      : "text-gray-300 hover:text-white"
                  }`}
                >
                  Community ▾
                </button>
                {activeMenu === "community" ? (
                  <div className="absolute top-full z-[9999] mt-2 w-56 rounded border border-white/10 bg-[#1e293b] shadow-lg">
                    {communityLinks.map((item) => (
                      <Link
                        key={item.href}
                        href={item.href}
                        className={`block rounded px-3 py-2 ${
                          isActive(item.href)
                            ? "bg-blue-500/20 text-blue-300"
                            : "text-gray-300 hover:bg-white/10"
                        }`}
                      >
                        {item.label}
                      </Link>
                    ))}
                  </div>
                ) : null}
              </div>

              <div className="relative">
                <button
                  type="button"
                  onClick={() => toggleMenu("affiliate")}
                  className={`shrink-0 rounded px-2 py-1 transition ${
                    isGroupActive(["/affiliate", "/payouts"])
                      ? "bg-blue-500/20 text-blue-300"
                      : "text-gray-300 hover:text-white"
                  }`}
                >
                  Affiliate ▾
                </button>
                {activeMenu === "affiliate" ? (
                  <div className="absolute top-full z-[9999] mt-2 w-56 rounded border border-white/10 bg-[#1e293b] shadow-lg">
                    {affiliateLinks.map((item) => (
                      <Link
                        key={item.href}
                        href={item.href}
                        className={`block rounded px-3 py-2 ${
                          isActive(item.href)
                            ? "bg-blue-500/20 text-blue-300"
                            : "text-gray-300 hover:bg-white/10"
                        }`}
                      >
                        {item.label}
                      </Link>
                    ))}
                  </div>
                ) : null}
              </div>
            </div>
          ) : null}
        </div>

        {/* RIGHT */}
        <div className="flex shrink-0 items-center gap-3 md:gap-4">
        {user ? (
          <>
            {showReturnToApp ? (
              <button
                type="button"
                onClick={handleReturnToApp}
                className="hidden shrink-0 rounded bg-blue-500 px-4 py-1.5 text-sm font-medium text-white transition hover:bg-blue-600 md:inline-flex"
              >
                Return to App
              </button>
            ) : null}

            <GettingStartedMobileEntry />

            {isAdmin ? (
              <Link
                href="/admin"
                className={`md:hidden shrink-0 rounded-lg px-2.5 py-1.5 text-xs font-medium transition ${
                  isGroupActive(["/admin"])
                    ? "bg-blue-500/20 text-blue-300"
                    : "text-gray-200 hover:text-blue-400"
                }`}
              >
                Admin
              </Link>
            ) : null}

            <div className="flex items-center gap-2.5 md:hidden">
              {!isHomePage
                ? notificationBellControl(
                    "text-xl leading-none",
                    "inline-flex items-center justify-center px-1 py-1",
                    "absolute -right-1 -top-0.5 min-w-[1rem] rounded-full bg-red-500 px-1 py-px text-center text-[10px] leading-tight tabular-nums text-white"
                  )
                : null}
              <button
                type="button"
                className="text-2xl leading-none text-white px-1 py-1"
                aria-expanded={isOpen}
                aria-label={isOpen ? "Close menu" : "Open menu"}
                onClick={() => {
                  setActiveMenu(null)
                  if (isOpen) {
                    setOpenSection(null)
                    setIsOpen(false)
                  } else {
                    setIsOpen(true)
                  }
                }}
              >
                ☰
              </button>
            </div>

            {!isHomePage ? (
              <div className="hidden items-center gap-3 md:flex">
                {isAdmin ? (
                  <Link href="/admin" className="text-sm hover:text-blue-400">
                    Admin
                  </Link>
                ) : null}

                {notificationBellControl("text-xl", "mr-2")}

                {profile?.is_beta_tester ? (
                  <Link
                    href="/beta"
                    className={`shrink-0 rounded border px-3 py-1.5 text-sm font-medium transition ${
                      isActive("/beta")
                        ? "border-yellow-400/50 bg-yellow-500/30 text-yellow-200"
                        : "border-yellow-400/30 bg-yellow-500/20 text-yellow-300 hover:bg-yellow-500/30"
                    }`}
                  >
                    Beta Hub
                  </Link>
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
                      <div className="h-8 w-8 animate-pulse rounded-full bg-white/10" aria-hidden />
                    )}
                    {!profileChromePending ? (
                      <span>{profile?.username ?? user?.email?.split("@")[0]}</span>
                    ) : (
                      <div className="h-4 w-20 animate-pulse rounded bg-white/10" />
                    )}
                  </button>

                  {accountMenuOpen ? (
                    <div className="absolute right-0 top-full z-50 mt-2 w-48 rounded-lg border border-gray-600 bg-[#1e293b] shadow-lg">
                      <button
                        type="button"
                        onClick={() => {
                          setAccountMenuOpen(false)
                          router.push("/settings#account")
                        }}
                        className="w-full px-4 py-2 text-left text-sm hover:bg-white/10"
                      >
                        Settings
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setAccountMenuOpen(false)
                          router.push("/help")
                        }}
                        className="w-full px-4 py-2 text-left text-sm hover:bg-white/10"
                      >
                        Help Center
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setAccountMenuOpen(false)
                          setBugReportOpen(true)
                        }}
                        className="w-full px-4 py-2 text-left text-sm hover:bg-white/10"
                      >
                        Report bug
                      </button>

                      <button
                        type="button"
                        onClick={async () => {
                          setAccountMenuOpen(false)
                          await supabase.auth.signOut()
                          router.push("/")
                        }}
                        className="w-full px-4 py-2 text-left text-sm text-red-400 hover:bg-red-500/10"
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
          <Link
            href="/login"
            className="shrink-0 rounded bg-blue-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600"
          >
            Login
          </Link>
        ) : (
          <div className="flex shrink-0 items-center gap-3">
            <Link href="/faq" className="md:hidden text-sm text-gray-200 hover:text-blue-400 transition">
              FAQ
            </Link>
            <button type="button" onClick={() => router.push("/login")} className="border px-4 py-2 rounded shrink-0">
              Login
            </button>
          </div>
        )}
        </div>
        </div>
      </div>

      {isOpen && user ? (
        <div className="max-h-[calc(100vh-4rem)] w-full overflow-y-auto border-t border-white/5 bg-[#0b1f3a] md:hidden">
          <div className="flex w-full flex-col gap-2 px-4 pb-3 pt-1.5 text-sm text-white md:px-6">
          {showReturnToApp ? (
            <button
              type="button"
              onClick={handleReturnToApp}
              className="rounded-lg bg-blue-500 px-3 py-2 font-medium text-white transition hover:bg-blue-600"
            >
              Return to App
            </button>
          ) : null}
          <Link
            href="/app"
            className={`rounded-lg px-3 py-2 transition ${
              isActive("/app")
                ? "bg-blue-500/20 text-blue-300"
                : "text-gray-300 hover:text-white"
            }`}
            onClick={closeMobile}
          >
            Input Trade
          </Link>

          <Link
            href="/dashboard"
            className={`rounded-lg px-3 py-2 transition ${
              isActive("/dashboard")
                ? "bg-blue-500/20 text-blue-300"
                : "text-gray-300 hover:text-white"
            }`}
            onClick={closeMobile}
          >
            Dashboard
          </Link>

          <Link
            href="/trades"
            className={`rounded-lg px-3 py-2 transition ${
              isActive("/trades")
                ? "bg-blue-500/20 text-blue-300"
                : "text-gray-300 hover:text-white"
            }`}
            onClick={closeMobile}
          >
            Trades
          </Link>

          {profileHref ? (
            <Link
              href={profileHref}
              className={`rounded-lg px-3 py-2 transition ${
                isGroupActive(["/profile"])
                  ? "bg-blue-500/20 text-blue-300"
                  : "text-gray-300 hover:text-white"
              }`}
              onClick={closeMobile}
            >
              Profile
            </Link>
          ) : (
            <span className="rounded-lg px-3 py-2 text-gray-500">Profile</span>
          )}

          <Link
            href="/messages"
            className={`flex items-center justify-between rounded-lg px-3 py-2 transition ${
              isActive("/messages")
                ? "bg-blue-500/20 text-blue-300"
                : "text-gray-300 hover:text-white"
            }`}
            onClick={() => {
              void handleToggleMessages()
              closeMobile()
            }}
          >
            <span>Messages</span>
            {unreadMessagesCount > 0 ? (
              <span className="bg-red-500 text-white text-xs px-2 py-0.5 rounded-full tabular-nums">
                {unreadMessagesCount > 9 ? "9+" : unreadMessagesCount}
              </span>
            ) : null}
          </Link>

          <div>
            <button
              type="button"
              className={`flex w-full items-center justify-between rounded-lg px-3 py-2 transition ${
                isGroupActive([
                  "/analytics",
                  "/backtest",
                  "/calendar",
                  "/achievements",
                  "/analyst",
                ])
                  ? "bg-blue-500/20 text-blue-300"
                  : "text-gray-300 hover:text-white"
              }`}
              onClick={() => toggleSection("analytics")}
            >
              <span>Analytics</span>
              <span className="text-gray-400 tabular-nums">{openSection === "analytics" ? "−" : "+"}</span>
            </button>
            {openSection === "analytics" ? (
              <div className="mt-1.5 space-y-1 pl-3 text-sm">
                {analyticsLinks.map((item) => (
                    <Link
                      key={item.href}
                      href={item.href}
                      className={`flex w-full items-center justify-between gap-2 rounded-lg px-3 py-1.5 ${
                        isActive(item.href)
                          ? "bg-blue-500/20 text-blue-300"
                          : item.proOnly && !isProActive(profile)
                            ? "text-gray-400 hover:bg-white/10"
                            : "hover:bg-white/10 text-gray-300"
                      }`}
                      onClick={closeMobile}
                    >
                      {analyticsLinkLabel(item)}
                      {item.proOnly && !isProActive(profile) ? proBadge : null}
                    </Link>
                  ))}
              </div>
            ) : null}
          </div>

          <div>
            <button
              type="button"
              className={`flex w-full items-center justify-between rounded-lg px-3 py-2 transition ${
                isGroupActive(["/community", "/feed", "/trade-rooms", "/leaderboard", "/explore"])
                  ? "bg-blue-500/20 text-blue-300"
                  : "text-gray-300 hover:text-white"
              }`}
              onClick={() => toggleSection("community")}
            >
              <span>Community</span>
              <span className="text-gray-400 tabular-nums">{openSection === "community" ? "−" : "+"}</span>
            </button>
            {openSection === "community" ? (
              <div className="mt-1.5 space-y-1 pl-3 text-sm">
                {communityLinks.map((item) => (
                  <Link
                    key={item.href}
                    href={item.href}
                    className={`block rounded-lg px-3 py-1.5 ${
                      isActive(item.href)
                        ? "bg-blue-500/20 text-blue-300"
                        : "hover:bg-white/10 text-gray-300"
                    }`}
                    onClick={closeMobile}
                  >
                    {item.label}
                  </Link>
                ))}
              </div>
            ) : null}
          </div>

          <div>
            <button
              type="button"
              className={`flex w-full items-center justify-between rounded-lg px-3 py-2 transition ${
                isGroupActive(["/affiliate", "/payouts"])
                  ? "bg-blue-500/20 text-blue-300"
                  : "text-gray-300 hover:text-white"
              }`}
              onClick={() => toggleSection("affiliate")}
            >
              <span>Affiliate</span>
              <span className="text-gray-400 tabular-nums">{openSection === "affiliate" ? "−" : "+"}</span>
            </button>
            {openSection === "affiliate" ? (
              <div className="mt-1.5 space-y-1 pl-3 text-sm">
                {affiliateLinks.map((item) => (
                  <Link
                    key={item.href}
                    href={item.href}
                    className={`block rounded-lg px-3 py-1.5 ${
                      isActive(item.href)
                        ? "bg-blue-500/20 text-blue-300"
                        : "hover:bg-white/10 text-gray-300"
                    }`}
                    onClick={closeMobile}
                  >
                    {item.label}
                  </Link>
                ))}
              </div>
            ) : null}
          </div>

          {profile?.is_beta_tester ? (
            <Link
              href="/beta"
              className={`flex items-center gap-2 rounded-lg px-3 py-2 transition ${
                isActive("/beta")
                  ? "border border-yellow-400/40 bg-yellow-500/25 text-yellow-200"
                  : "border border-yellow-400/25 bg-yellow-500/15 text-yellow-300 hover:bg-yellow-500/25"
              }`}
              onClick={closeMobile}
            >
              <span>Beta Hub</span>
              {betaBadge}
            </Link>
          ) : null}

          <div className="flex flex-col gap-1 border-t border-white/5 pt-1.5">
            {isAdmin ? (
              <Link
                href="/admin"
                className="rounded-lg px-3 py-2 text-white hover:text-blue-400"
                onClick={closeMobile}
              >
                Admin
              </Link>
            ) : null}

            <Link
              href="/settings#account"
              className="rounded-lg px-3 py-2 text-white hover:text-blue-400"
              onClick={closeMobile}
            >
              Settings
            </Link>
            <Link
              href="/help"
              className="rounded-lg px-3 py-2 text-white hover:text-blue-400"
              onClick={closeMobile}
            >
              Help Center
            </Link>
            <button
              type="button"
              className="rounded-lg px-3 py-2 text-left text-white hover:text-blue-400"
              onClick={() => {
                closeMobile()
                setBugReportOpen(true)
              }}
            >
              Report bug
            </button>

            <button
              type="button"
              className="flex w-full items-center justify-between rounded-lg px-3 py-2 text-left text-white hover:text-blue-400"
              onClick={() => {
                void handleToggleNotifications()
                closeMobile()
                router.push("/notifications")
              }}
            >
              <span>Notifications</span>
              {unreadCount > 0 ? (
                <span className="bg-red-500 text-white text-xs px-2 py-0.5 rounded-full tabular-nums">
                  {badgeText(unreadCount)}
                </span>
              ) : null}
            </button>

            <button
              type="button"
              className="w-full rounded-lg px-3 py-2 text-left text-sm text-red-400 hover:text-red-300"
              onClick={async () => {
                closeMobile()
                await supabase.auth.signOut()
                router.push("/")
              }}
            >
              Sign Out
            </button>
          </div>
          </div>
        </div>
      ) : null}

      <BugReportModal open={bugReportOpen} onClose={() => setBugReportOpen(false)} />
    </div>
  )
}