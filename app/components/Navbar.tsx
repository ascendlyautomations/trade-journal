"use client"

import Link from "next/link"
import { useCallback, useEffect, useState, useRef } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter, usePathname } from "next/navigation"
import { useUserProfile } from "../../lib/useUserProfile"
import { isProActive } from "../../lib/subscription"
import { getCurrentAdminCheckResult } from "../../lib/adminUsers"

export default function Navbar() {
  const { user, profile, loading } = useUserProfile()
  const profileRouteId = profile?.id ?? user?.id ?? null
  const profileChromePending = !!user && loading && !profile

  const [isOpen, setIsOpen] = useState(false)
  const [openSection, setOpenSection] = useState<string | null>(null)
  const [activeMenu, setActiveMenu] = useState<string | null>(null)
  const [accountMenuOpen, setAccountMenuOpen] = useState(false)
  const [unreadMessagesCount, setUnreadMessagesCount] = useState(0)
  const [unreadCount, setUnreadCount] = useState(0)
  const [isAdmin, setIsAdmin] = useState(false)
  const [hasFetchedNotifications, setHasFetchedNotifications] = useState(false)
  const [hasFetchedMessages, setHasFetchedMessages] = useState(false)
  const [hasFetchedAdmin, setHasFetchedAdmin] = useState(false)

  const router = useRouter()
  const pathname = usePathname()
  const isHomePage = pathname === "/"
  const isActive = (path: string) => pathname === path
  const isGroupActive = (paths: string[]) =>
    paths.some((p) => pathname.startsWith(p))

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
    const { count } = await supabase
      .from("direct_messages")
      .select("*", { count: "exact", head: true })
      .eq("recipient_id", user.id)
      .eq("is_read", false)

    setUnreadMessagesCount(count ?? 0)
  }, [user])

  const fetchUnread = useCallback(async () => {
    if (!user?.id) return

    const { count, error } = await supabase
      .from("notifications")
      .select("*", { count: "exact", head: true })
      .eq("user_id", user.id)
      .eq("type", "message")
      .eq("read", false)

    if (error) {
      console.error("[navbar] unread notifications fetch failed", {
        query:
          "notifications select count where user_id = currentUser and type = message and read = false",
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

    const uid = user.id

    const channel = supabase.channel(`notif-${uid}`)

    channel.on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table: "notifications",
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
    { label: "Backtest Stats", href: "/backtest", proOnly: true },
  ]

  const betaBadge = (
    <span className="shrink-0 text-[10px] px-2 py-[2px] rounded bg-yellow-500/20 text-yellow-300 border border-yellow-400/30">
      BETA
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

  const affiliateLinks: { label: string; href: string }[] = [
    { label: "Affiliate Dashboard", href: "/affiliate" },
    { label: "Affiliate Payouts", href: "/payouts" },
    { label: "Become an Affiliate", href: "/affiliate?apply=true" },
  ]

  const closeMobile = () => {
    setIsOpen(false)
    setOpenSection(null)
  }

  return (
    <div ref={navRef} className="fixed top-0 left-0 z-[9999] w-full overflow-visible text-gray-100">
      <div className="flex h-16 w-full shrink-0 items-center border-b border-white/5 bg-[#0b1f3a]">
        <div className="flex h-full w-full items-center justify-between px-4 md:px-6">
        {/* LEFT */}
        <div className="flex min-w-0 items-center gap-3">
          <Link
            href="/"
            className="font-bold text-xl shrink-0 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent"
          >
            TradeTraxs
          </Link>

          {!user && !isHomePage ? (
            <Link href="/faq" className="hidden md:inline text-sm text-gray-200 hover:text-blue-400 transition">
              FAQ
            </Link>
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
              {profileRouteId ? (
                <Link
                  href={`/profile/${profileRouteId}`}
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
                    {analyticsLinks.map((item) =>
                      item.proOnly && !isProActive(profile) ? (
                        <div
                          key={item.label}
                          className="flex w-full items-center justify-between gap-2 px-4 py-2 text-gray-400"
                        >
                          {analyticsLinkLabel(item)}
                          <span className="shrink-0">🔒</span>
                        </div>
                      ) : (
                        <Link
                          key={item.href}
                          href={item.href}
                          className={`flex w-full items-center justify-between gap-2 rounded px-3 py-2 ${
                            isActive(item.href)
                              ? "bg-blue-500/20 text-blue-300"
                              : "text-gray-300 hover:bg-white/10"
                          }`}
                        >
                          {analyticsLinkLabel(item)}
                        </Link>
                      )
                    )}
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
            <button
              type="button"
              className="text-2xl leading-none text-white md:hidden px-1 py-1"
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

            <div className="hidden items-center gap-3 md:flex">
              {isAdmin ? (
                <Link href="/admin" className="text-sm hover:text-blue-400">
                  Admin
                </Link>
              ) : null}

              <div
                className="relative mr-2 shrink-0 cursor-pointer"
                role="button"
                tabIndex={0}
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
                <div className="text-xl text-white" aria-hidden>
                  🔔
                </div>
                {unreadCount > 0 ? (
                  <span className="absolute -right-2 -top-1 min-w-[1.25rem] rounded-full bg-red-500 px-1.5 py-0.5 text-center text-xs tabular-nums text-white">
                    {badgeText(unreadCount)}
                  </span>
                ) : null}
              </div>

              <div className="profile-menu relative">
                <button
                  type="button"
                  onClick={() => {
                    void handleToggleAccountMenu()
                  }}
                  className="flex items-center gap-2 rounded border px-3 py-1"
                >
                  {!profileChromePending ? (
                    <img src={profile?.avatar_url} className="h-8 w-8 rounded-full" alt="" />
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
                        router.push("/feedback")
                      }}
                      className="w-full px-4 py-2 text-left text-sm hover:bg-white/10"
                    >
                      Feedback
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setAccountMenuOpen(false)
                        router.push("/support")
                      }}
                      className="w-full px-4 py-2 text-left text-sm hover:bg-white/10"
                    >
                      Support
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

          {profileRouteId ? (
            <Link
              href={`/profile/${profileRouteId}`}
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
                {analyticsLinks.map((item) =>
                  item.proOnly && !isProActive(profile) ? (
                    <span
                      key={item.label}
                      className="flex w-full items-center justify-between gap-2 rounded-lg px-3 py-1.5 text-gray-400"
                    >
                      {analyticsLinkLabel(item)}
                      <span className="shrink-0">🔒</span>
                    </span>
                  ) : (
                    <Link
                      key={item.href}
                      href={item.href}
                      className={`flex w-full items-center justify-between gap-2 rounded-lg px-3 py-1.5 ${
                        isActive(item.href)
                          ? "bg-blue-500/20 text-blue-300"
                          : "hover:bg-white/10 text-gray-300"
                      }`}
                      onClick={closeMobile}
                    >
                      {analyticsLinkLabel(item)}
                    </Link>
                  )
                )}
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
              href="/feedback"
              className="rounded-lg px-3 py-2 text-white hover:text-blue-400"
              onClick={closeMobile}
            >
              Feedback
            </Link>
            <Link
              href="/support"
              className="rounded-lg px-3 py-2 text-white hover:text-blue-400"
              onClick={closeMobile}
            >
              Support
            </Link>

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
    </div>
  )
}