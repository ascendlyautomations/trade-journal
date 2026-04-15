"use client"

import Link from "next/link"
import { useCallback, useEffect, useState, useRef } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter, usePathname } from "next/navigation"
import { useUserProfile } from "../../lib/useUserProfile"
import { isProActive } from "../../lib/subscription"

const ADMIN_ID = "PASTE_YOUR_SUPABASE_USER_ID_HERE"

export default function Navbar() {
  const { user, profile, loading } = useUserProfile()

  const [activeMenu, setActiveMenu] = useState<string | null>(null)
  const [accountMenuOpen, setAccountMenuOpen] = useState(false)
  const [isOpen, setIsOpen] = useState(false)
  const [openSection, setOpenSection] = useState<string | null>(null)
  const [unreadMessagesCount, setUnreadMessagesCount] = useState(0)
  const [unreadCount, setUnreadCount] = useState(0)

  const router = useRouter()
  const pathname = usePathname()
  const isHome = pathname === "/"

  const navRef = useRef<HTMLDivElement>(null)

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

  useEffect(() => {
    if (user) void fetchUnreadMessages()
    // fetchUnreadMessages is redeclared each render; only user drives refetch
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user])

  const fetchUnread = useCallback(async () => {
    if (!user?.id) return

    const { data, error } = await supabase
      .from("notifications")
      .select("id")
      .eq("user_id", user.id)
      .eq("read", false)

    if (error) {
      console.error("Unread fetch error:", error)
      return
    }

    setUnreadCount(data?.length || 0)
  }, [user])

  useEffect(() => {
    if (!user?.id) {
      setUnreadCount(0)
      return
    }
    void fetchUnread()
  }, [user, fetchUnread])

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

  useEffect(() => {
    setIsOpen(false)
    setOpenSection(null)
  }, [pathname])

  if (loading) return null

  const appNavMenus = [
    {
      key: "trades",
      label: "Trades",
      items: [
        { label: "Input Trade", link: "/app" },
        { label: "Trade History", link: "/trades" },
        { label: "Backtest Data", link: "/backtest" },
      ],
    },
    {
      key: "analytics",
      label: "Analytics",
      items: [
        { label: "Calendar", link: "/calendar" },
        isProActive(profile)
          ? { label: "AI Analyst", link: "/analyst", highlight: true }
          : { label: "AI Analyst 🔒", link: null },
      ],
    },
    {
      key: "community",
      label: "Community",
      items: [
        {
          label: "My Profile",
          action: () => router.push(`/profile/${profile?.id}`),
          className: `${pathname.includes("/profile") ? "text-blue-400" : "text-gray-300"} hover:text-blue-300 font-medium`,
        },
        { label: "Feed", action: () => router.push("/feed") },
        {
          label: "Messages",
          action: () => router.push("/messages"),
          badge: unreadMessagesCount,
        },
        { label: "Trade Rooms", action: () => router.push("/community") },
        { label: "Leaderboard", action: () => router.push("/leaderboard") },
        { label: "Explore", action: () => router.push("/explore") },
      ],
    },
    {
      key: "earnings",
      label: "Earnings",
      items: [
        { label: "Affiliate Dashboard", link: "/affiliate", highlight: true },
        { label: "Payouts (Soon)", link: null },
      ],
    },
  ]

  const closeMobile = () => {
    setIsOpen(false)
    setOpenSection(null)
  }

  return (
    <div
      ref={navRef}
      className="w-full border-b border-white/10 bg-[#0f172a] text-gray-100 relative z-[9999] overflow-visible"
    >
      <div className="flex items-center justify-between px-4 md:px-6 py-3">
        {/* LEFT */}
        <div className="flex items-center gap-8 min-w-0">
          <Link
            href="/"
            className="font-bold text-xl shrink-0 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent"
          >
            TradeTraxs
          </Link>

          {!user ? (
            <Link href="/faq" className="hidden md:inline text-sm text-gray-200 hover:text-blue-400 transition">
              FAQ
            </Link>
          ) : null}

          {!isHome && user ? (
            <div className="hidden md:flex items-center gap-6 text-sm">
              <Link href="/dashboard" className="hover:text-blue-400">
                Dashboard
              </Link>

              {appNavMenus.map((menu) => (
                <div key={menu.key} className="relative">
                  <button type="button" onClick={() => toggleMenu(menu.key)} className="hover:text-blue-400">
                    {menu.label} ▾
                  </button>

                  {activeMenu === menu.key ? (
                    <div className="absolute top-full mt-2 w-56 bg-[#1e293b] border border-white/10 rounded shadow-lg z-[9999]">
                      {menu.items.map((item, i: number) => (
                        <div key={i}>
                          {"link" in item && item.link ? (
                            <Link
                              href={item.link}
                              className={`block px-4 py-2 hover:bg-white/10 ${item.highlight ? "text-emerald-400 font-semibold" : ""}`}
                            >
                              {item.label}
                            </Link>
                          ) : "action" in item && item.action ? (
                            <button
                              type="button"
                              onClick={item.action}
                              className={`flex justify-between w-full px-4 py-2 hover:bg-white/10 text-left ${item.className || ""}`}
                            >
                              {item.label}
                              {"badge" in item && (item.badge ?? 0) > 0 ? (
                                <span className="bg-red-500 text-xs px-2 rounded-full">{item.badge}</span>
                              ) : null}
                            </button>
                          ) : (
                            <div className="px-4 py-2 text-gray-400">{item.label}</div>
                          )}
                        </div>
                      ))}
                    </div>
                  ) : null}
                </div>
              ))}

              <Link href="/suggestions" className="hover:text-blue-400">
                Feedback
              </Link>
            </div>
          ) : null}
        </div>

        {/* RIGHT */}
        {!user ? (
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
              {user?.id === ADMIN_ID ? (
                <Link href="/admin/feedback" className="text-sm hover:text-blue-400">
                  Admin
                </Link>
              ) : null}

              <div
                className="relative mr-2 cursor-pointer shrink-0"
                role="button"
                tabIndex={0}
                onClick={() => {
                  setAccountMenuOpen(false)
                  setActiveMenu(null)
                  router.push("/notifications")
                }}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault()
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
                    {unreadCount > 9 ? "9+" : unreadCount}
                  </span>
                ) : null}
              </div>

              <div className="relative profile-menu">
                <button
                  type="button"
                  onClick={() => {
                    setActiveMenu(null)
                    setAccountMenuOpen((open) => !open)
                  }}
                  className="flex items-center gap-2 border px-3 py-1 rounded"
                >
                  {profile?.avatar_url ? (
                    <img src={profile.avatar_url} className="w-6 h-6 rounded-full" alt="" />
                  ) : (
                    <div className="w-6 h-6 rounded-full bg-gray-500" aria-hidden />
                  )}
                  <span>{profile?.name || profile?.username}</span>
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

      {isOpen && user ? (
        <div className="md:hidden px-4 pb-4 space-y-2 bg-[#0B1220] border-t border-white/10 pt-2">
          <Link href="/dashboard" className="block py-2 text-white hover:text-blue-400" onClick={closeMobile}>
            Dashboard
          </Link>

          <div>
            <button
              type="button"
              className="w-full flex justify-between items-center py-2 text-white hover:text-blue-400 text-left"
              onClick={() => setOpenSection(openSection === "trades" ? null : "trades")}
            >
              Trades
              <span className="text-gray-400 tabular-nums">{openSection === "trades" ? "−" : "+"}</span>
            </button>
            {openSection === "trades" ? (
              <div className="pl-4 flex flex-col gap-2 text-sm text-gray-300">
                <Link href="/app" className="hover:text-white py-0.5" onClick={closeMobile}>
                  Input Trade
                </Link>
                <Link href="/trades" className="hover:text-white py-0.5" onClick={closeMobile}>
                  Trade History
                </Link>
                <Link href="/backtest" className="hover:text-white py-0.5" onClick={closeMobile}>
                  Backtest Data
                </Link>
              </div>
            ) : null}
          </div>

          <div>
            <button
              type="button"
              className="w-full flex justify-between items-center py-2 text-white hover:text-blue-400 text-left"
              onClick={() => setOpenSection(openSection === "analytics" ? null : "analytics")}
            >
              Analytics
              <span className="text-gray-400 tabular-nums">{openSection === "analytics" ? "−" : "+"}</span>
            </button>
            {openSection === "analytics" ? (
              <div className="pl-4 flex flex-col gap-2 text-sm text-gray-300">
                <Link href="/calendar" className="hover:text-white py-0.5" onClick={closeMobile}>
                  Calendar
                </Link>
                {isProActive(profile) ? (
                  <Link href="/analyst" className="hover:text-emerald-300 font-medium py-0.5" onClick={closeMobile}>
                    AI Analyst
                  </Link>
                ) : (
                  <span className="text-gray-500 py-0.5">AI Analyst 🔒</span>
                )}
              </div>
            ) : null}
          </div>

          <div>
            <button
              type="button"
              className="w-full flex justify-between items-center py-2 text-white hover:text-blue-400 text-left"
              onClick={() => setOpenSection(openSection === "community" ? null : "community")}
            >
              Community
              <span className="text-gray-400 tabular-nums">{openSection === "community" ? "−" : "+"}</span>
            </button>
            {openSection === "community" ? (
              <div className="pl-4 flex flex-col gap-2 text-sm text-gray-300">
                {profile?.id ? (
                  <Link
                    href={`/profile/${profile.id}`}
                    className={`hover:text-white py-0.5 ${pathname.includes("/profile") ? "text-blue-400" : ""}`}
                    onClick={closeMobile}
                  >
                    My Profile
                  </Link>
                ) : (
                  <span className="text-gray-500 py-0.5">My Profile</span>
                )}
                <Link href="/feed" className="hover:text-white py-0.5" onClick={closeMobile}>
                  Feed
                </Link>
                <Link href="/community" className="hover:text-white py-0.5" onClick={closeMobile}>
                  Trade Rooms
                </Link>
                <Link href="/leaderboard" className="hover:text-white py-0.5" onClick={closeMobile}>
                  Leaderboard
                </Link>
                <Link href="/explore" className="hover:text-white py-0.5" onClick={closeMobile}>
                  Explore
                </Link>
              </div>
            ) : null}
          </div>

          <div>
            <button
              type="button"
              className="w-full flex justify-between items-center py-2 text-white hover:text-blue-400 text-left"
              onClick={() => setOpenSection(openSection === "earnings" ? null : "earnings")}
            >
              Earnings
              <span className="text-gray-400 tabular-nums">{openSection === "earnings" ? "−" : "+"}</span>
            </button>
            {openSection === "earnings" ? (
              <div className="pl-4 flex flex-col gap-2 text-sm text-gray-300">
                <Link href="/affiliate" className="hover:text-emerald-300 font-medium py-0.5" onClick={closeMobile}>
                  Affiliate Dashboard
                </Link>
                <span className="text-gray-500 py-0.5">Payouts (Soon)</span>
              </div>
            ) : null}
          </div>

          <Link href="/suggestions" className="block py-2 text-white hover:text-blue-400" onClick={closeMobile}>
            Feedback
          </Link>

          <Link
            href="/messages"
            className="flex items-center justify-between py-2 text-white hover:text-blue-400"
            onClick={closeMobile}
          >
            <span>Messages</span>
            {unreadMessagesCount > 0 ? (
              <span className="bg-red-500 text-white text-xs px-2 py-0.5 rounded-full tabular-nums">{unreadMessagesCount}</span>
            ) : null}
          </Link>

          {profile?.id ? (
            <Link href={`/profile/${profile.id}`} className="block py-2 text-white hover:text-blue-400" onClick={closeMobile}>
              Profile
            </Link>
          ) : (
            <span className="block py-2 text-gray-500">Profile</span>
          )}

          <Link href="/settings" className="block py-2 text-white hover:text-blue-400" onClick={closeMobile}>
            Settings
          </Link>

          <div className="border-t border-white/10 pt-2 space-y-2">
            {user?.id === ADMIN_ID ? (
              <Link href="/admin/feedback" className="block py-2 text-white hover:text-blue-400" onClick={closeMobile}>
                Admin
              </Link>
            ) : null}

            <button
              type="button"
              className="w-full flex items-center justify-between py-2 text-left text-white hover:text-blue-400"
              onClick={() => {
                closeMobile()
                setAccountMenuOpen(false)
                setActiveMenu(null)
                router.push("/notifications")
              }}
            >
              <span>Notifications</span>
              {unreadCount > 0 ? (
                <span className="bg-red-500 text-white text-xs px-2 py-0.5 rounded-full tabular-nums">
                  {unreadCount > 9 ? "9+" : unreadCount}
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
      ) : null}
    </div>
  )
}