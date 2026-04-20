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

  const [activeMenu, setActiveMenu] = useState<string | null>(null)
  const [accountMenuOpen, setAccountMenuOpen] = useState(false)
  const [isOpen, setIsOpen] = useState(false)
  const [openSection, setOpenSection] = useState<string | null>(null)
  const [unreadMessagesCount, setUnreadMessagesCount] = useState(0)
  const [unreadCount, setUnreadCount] = useState(0)
  const [isAdmin, setIsAdmin] = useState(false)
  const [isReady, setIsReady] = useState(false)
  const [notificationsOpen, setNotificationsOpen] = useState(false)
  const [messagesOpen, setMessagesOpen] = useState(false)
  const [hasFetchedNotifications, setHasFetchedNotifications] = useState(false)
  const [hasFetchedMessages, setHasFetchedMessages] = useState(false)
  const [hasFetchedAdmin, setHasFetchedAdmin] = useState(false)

  const router = useRouter()
  const pathname = usePathname()
  const isHomePage = pathname === "/"

  const navRef = useRef<HTMLDivElement>(null)
  const badgeText = (count: number) => (count > 99 ? "99+" : String(count))

  // CLOSE ON OUTSIDE CLICK (nav + profile menu)
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

  async function fetchUnreadMessages() {
    if (!user?.id) return
    const { count } = await supabase
      .from("direct_messages")
      .select("*", { count: "exact", head: true })
      .eq("recipient_id", user.id)
      .eq("is_read", false)

    setUnreadMessagesCount(count ?? 0)
  }

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

  function toggleMenu(menu: string) {
    setAccountMenuOpen(false)
    setActiveMenu(activeMenu === menu ? null : menu)
  }

  const toggleSection = (section: string) => {
    setOpenSection((prev) => (prev === section ? null : section))
  }

  const handleToggleNotifications = async () => {
    setNotificationsOpen((prev) => !prev)

    if (!hasFetchedNotifications) {
      await fetchUnread()
      setHasFetchedNotifications(true)
    }
  }

  const handleToggleMessages = async () => {
    setMessagesOpen((prev) => !prev)

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
  }, [pathname])

  useEffect(() => {
    if (!loading) {
      setIsReady(true)
    }
  }, [loading])

  const analyticsLinks: {
    label: string
    href: string
    proOnly?: boolean
  }[] = [
    { label: "Trade History", href: "/trade-history" },
    { label: "Backtest Stats", href: "/backtest" },
    { label: "Calendar", href: "/calendar" },
    { label: "Achievements", href: "/achievements" },
    { label: "AI Analysis", href: "/ai", proOnly: true },
  ]

  const communityLinks: { label: string; href: string }[] = [
    { label: "Feed", href: "/feed" },
    { label: "Trade Rooms", href: "/trade-rooms" },
    { label: "Leaderboard", href: "/leaderboard" },
    { label: "Explore", href: "/explore" },
  ]

  const affiliateLinks: { label: string; href: string }[] = [
    { label: "Affiliate Dashboard", href: "/affiliate" },
    { label: "Payouts", href: "/payouts" },
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
        <div className="flex min-w-0 items-center gap-6">
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
            <div className="hidden md:flex items-center gap-6 text-sm">
              <Link href="/dashboard" className="hover:text-blue-400">
                Dashboard
              </Link>

              <Link href="/input-trade" className="hover:text-blue-400">
                Input Trade
              </Link>

              {profile?.id ? (
                <Link
                  href={`/profile/${profile.id}`}
                  className={`hover:text-blue-400 ${pathname.includes("/profile") ? "text-blue-400" : ""}`}
                >
                  Profile
                </Link>
              ) : (
                <span className="text-gray-500">Profile</span>
              )}

              <Link
                href="/messages"
                className="hover:text-blue-400 inline-flex items-center gap-2"
                onClick={() => {
                  void handleToggleMessages()
                }}
              >
                Messages
                {unreadMessagesCount > 0 ? (
                  <span className="bg-red-500 text-white text-xs px-1.5 py-0.5 rounded-full tabular-nums">
                    {unreadMessagesCount > 9 ? "9+" : unreadMessagesCount}
                  </span>
                ) : null}
              </Link>

              <div className="relative">
                <button type="button" onClick={() => toggleMenu("analytics")} className="hover:text-blue-400">
                  Analytics ▾
                </button>
                {activeMenu === "analytics" ? (
                  <div className="absolute top-full mt-2 w-56 bg-[#1e293b] border border-white/10 rounded shadow-lg z-[9999]">
                    {analyticsLinks.map((item) =>
                      item.proOnly && !isProActive(profile) ? (
                        <div key={item.label} className="px-4 py-2 text-gray-400">
                          {item.label} 🔒
                        </div>
                      ) : (
                        <Link
                          key={item.href}
                          href={item.href}
                          className="block px-4 py-2 hover:bg-white/10 text-gray-200"
                        >
                          {item.label}
                        </Link>
                      )
                    )}
                  </div>
                ) : null}
              </div>

              <div className="relative">
                <button type="button" onClick={() => toggleMenu("community")} className="hover:text-blue-400">
                  Community ▾
                </button>
                {activeMenu === "community" ? (
                  <div className="absolute top-full mt-2 w-56 bg-[#1e293b] border border-white/10 rounded shadow-lg z-[9999]">
                    {communityLinks.map((item) => (
                      <Link
                        key={item.href}
                        href={item.href}
                        className="block px-4 py-2 hover:bg-white/10 text-gray-200"
                      >
                        {item.label}
                      </Link>
                    ))}
                  </div>
                ) : null}
              </div>

              <div className="relative">
                <button type="button" onClick={() => toggleMenu("affiliate")} className="hover:text-blue-400">
                  Affiliate ▾
                </button>
                {activeMenu === "affiliate" ? (
                  <div className="absolute top-full mt-2 w-56 bg-[#1e293b] border border-white/10 rounded shadow-lg z-[9999]">
                    {affiliateLinks.map((item) => (
                      <Link
                        key={item.href}
                        href={item.href}
                        className="block px-4 py-2 hover:bg-white/10 text-gray-200"
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
        {isHomePage ? (
          user ? (
            profile?.id ? (
              <Link
                href={`/profile/${profile.id}`}
                className="shrink-0 rounded border border-white/20 px-4 py-2 text-sm font-medium text-white transition hover:bg-white/10"
              >
                Profile
              </Link>
            ) : (
              <span className="shrink-0 rounded border border-white/10 px-4 py-2 text-sm text-gray-500">
                Profile
              </span>
            )
          ) : (
            <Link
              href="/login"
              className="shrink-0 rounded bg-blue-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600"
            >
              Login
            </Link>
          )
        ) : !user ? (
          <div className="flex items-center gap-3 shrink-0">
            <Link href="/faq" className="md:hidden text-sm text-gray-200 hover:text-blue-400 transition">
              FAQ
            </Link>
            <button type="button" onClick={() => router.push("/login")} className="border px-4 py-2 rounded shrink-0">
              Login
            </button>
          </div>
        ) : (
          <div className="flex items-center justify-end gap-2 shrink-0">
            <button
              type="button"
              className="md:hidden text-white text-2xl leading-none px-1 py-1"
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

            <div className="hidden md:flex items-center gap-3 shrink-0">
              {isAdmin ? (
                <Link href="/admin" className="text-sm hover:text-blue-400">
                  Admin
                </Link>
              ) : null}

              <div
                className="relative mr-2 cursor-pointer shrink-0"
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
                <div className="text-white text-xl" aria-hidden>
                  🔔
                </div>
                {unreadCount > 0 ? (
                  <span className="absolute -top-1 -right-2 bg-red-500 text-white text-xs px-1.5 py-0.5 rounded-full tabular-nums min-w-[1.25rem] text-center">
                    {badgeText(unreadCount)}
                  </span>
                ) : null}
              </div>

              <div className="relative profile-menu">
                <button
                  type="button"
                  onClick={() => {
                    void handleToggleAccountMenu()
                  }}
                  className="flex items-center gap-2 border px-3 py-1 rounded"
                >
                  {isReady ? (
                    <img src={profile?.avatar_url} className="w-8 h-8 rounded-full" alt="" />
                  ) : (
                    <div className="w-8 h-8 rounded-full bg-white/10 animate-pulse" aria-hidden />
                  )}
                  {isReady ? (
                    <span>{profile?.username}</span>
                  ) : (
                    <div className="w-20 h-4 bg-white/10 rounded animate-pulse" />
                  )}
                </button>

                {accountMenuOpen ? (
                  <div className="absolute right-0 top-full mt-2 w-48 bg-[#1e293b] border border-gray-600 rounded-lg shadow-lg z-50">
                    <button
                      type="button"
                      onClick={() => {
                        setAccountMenuOpen(false)
                        router.push("/settings")
                      }}
                      className="px-4 py-2 hover:bg-white/10 w-full text-left text-sm"
                    >
                      Settings
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setAccountMenuOpen(false)
                        router.push("/feedback")
                      }}
                      className="px-4 py-2 hover:bg-white/10 w-full text-left text-sm"
                    >
                      Feedback
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setAccountMenuOpen(false)
                        router.push("/support")
                      }}
                      className="px-4 py-2 hover:bg-white/10 w-full text-left text-sm"
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
                      className="px-4 py-2 text-red-400 hover:bg-red-500/10 w-full text-left text-sm"
                    >
                      Sign Out
                    </button>
                  </div>
                ) : null}
              </div>
            </div>
          </div>
        )}
        </div>
        </div>
      </div>

      {isOpen && user && !isHomePage ? (
        <div className="w-full border-t border-white/5 bg-[#0b1f3a] md:hidden">
          <div className="flex w-full flex-col gap-3 px-4 pb-4 pt-2 text-sm text-white md:px-6">
          <Link href="/dashboard" className="py-2 hover:text-blue-400" onClick={closeMobile}>
            Dashboard
          </Link>

          <Link href="/input-trade" className="py-2 hover:text-blue-400" onClick={closeMobile}>
            Input Trade
          </Link>

          {profile?.id ? (
            <Link
              href={`/profile/${profile.id}`}
              className={`py-2 hover:text-blue-400 ${pathname.includes("/profile") ? "text-blue-400" : ""}`}
              onClick={closeMobile}
            >
              Profile
            </Link>
          ) : (
            <span className="py-2 text-gray-500">Profile</span>
          )}

          <Link
            href="/messages"
            className="flex items-center justify-between py-2 hover:text-blue-400"
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
              className="w-full flex justify-between items-center py-2 cursor-pointer text-left text-white hover:text-blue-400"
              onClick={() => toggleSection("analytics")}
            >
              <span>Analytics</span>
              <span className="text-gray-400 tabular-nums">{openSection === "analytics" ? "−" : "+"}</span>
            </button>
            {openSection === "analytics" ? (
              <div className="pl-4 mt-2 space-y-2 text-sm">
                {analyticsLinks.map((item) =>
                  item.proOnly && !isProActive(profile) ? (
                    <span key={item.label} className="block text-gray-400">
                      {item.label} 🔒
                    </span>
                  ) : (
                    <Link
                      key={item.href}
                      href={item.href}
                      className="block text-gray-400 hover:text-white"
                      onClick={closeMobile}
                    >
                      {item.label}
                    </Link>
                  )
                )}
              </div>
            ) : null}
          </div>

          <div>
            <button
              type="button"
              className="w-full flex justify-between items-center py-2 cursor-pointer text-left text-white hover:text-blue-400"
              onClick={() => toggleSection("community")}
            >
              <span>Community</span>
              <span className="text-gray-400 tabular-nums">{openSection === "community" ? "−" : "+"}</span>
            </button>
            {openSection === "community" ? (
              <div className="pl-4 mt-2 space-y-2 text-sm">
                {communityLinks.map((item) => (
                  <Link
                    key={item.href}
                    href={item.href}
                    className="block text-gray-400 hover:text-white"
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
              className="w-full flex justify-between items-center py-2 cursor-pointer text-left text-white hover:text-blue-400"
              onClick={() => toggleSection("affiliate")}
            >
              <span>Affiliate</span>
              <span className="text-gray-400 tabular-nums">{openSection === "affiliate" ? "−" : "+"}</span>
            </button>
            {openSection === "affiliate" ? (
              <div className="pl-4 mt-2 space-y-2 text-sm">
                {affiliateLinks.map((item) => (
                  <Link
                    key={item.href}
                    href={item.href}
                    className="block text-gray-400 hover:text-white"
                    onClick={closeMobile}
                  >
                    {item.label}
                  </Link>
                ))}
              </div>
            ) : null}
          </div>

          <div className="flex flex-col gap-2 border-t border-white/5 pt-2">
            {isAdmin ? (
              <Link href="/admin" className="py-2 text-white hover:text-blue-400" onClick={closeMobile}>
                Admin
              </Link>
            ) : null}

            <Link href="/settings" className="py-2 text-white hover:text-blue-400" onClick={closeMobile}>
              Settings
            </Link>
            <Link href="/feedback" className="py-2 text-white hover:text-blue-400" onClick={closeMobile}>
              Feedback
            </Link>
            <Link href="/support" className="py-2 text-white hover:text-blue-400" onClick={closeMobile}>
              Support
            </Link>

            <button
              type="button"
              className="w-full flex items-center justify-between py-2 text-left text-white hover:text-blue-400"
              onClick={() => {
                void handleToggleNotifications()
                closeMobile()
                setAccountMenuOpen(false)
                setActiveMenu(null)
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
              className="w-full py-2 text-left text-red-400 hover:text-red-300 text-sm"
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