"use client"

import Link from "next/link"
import { useCallback, useEffect, useState, useRef } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter, usePathname } from "next/navigation"
import { useUserProfile } from "../../lib/useUserProfile"

export default function Navbar() {
  const { user, profile, loading } = useUserProfile()

  const [activeMenu, setActiveMenu] = useState<string | null>(null)
  const [accountMenuOpen, setAccountMenuOpen] = useState(false)
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
        return
      }

      if (!el.closest(".profile-menu")) {
        setAccountMenuOpen(false)
      }
    }

    document.addEventListener("mousedown", handleClickOutside)
    return () => document.removeEventListener("mousedown", handleClickOutside)
  }, [])

  useEffect(() => {
    if (user) fetchUnreadMessages()
  }, [user])

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
  }, [user?.id])

  useEffect(() => {
    if (!user?.id) {
      setUnreadCount(0)
      return
    }
    void fetchUnread()
  }, [user?.id, fetchUnread])

  useEffect(() => {
    if (!user?.id) return

    const uid = user.id

    const channel = supabase
      .channel(`notif-${uid}`)
      .on(
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
      .subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
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

  function toggleMenu(menu: string) {
    setAccountMenuOpen(false)
    setActiveMenu(activeMenu === menu ? null : menu)
  }

  if (loading) return null

  return (
    <div
      ref={navRef}
      className="w-full px-6 py-3 border-b border-white/10 flex justify-between items-center bg-[#0f172a] text-gray-100 relative z-[9999] overflow-visible"
    >
      {/* LEFT */}
      <div className="flex items-center gap-8">

        <Link href="/" className="font-bold text-xl bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
          TradeTraxs
        </Link>

        {!user ? (
          <Link
            href="/faq"
            className="text-sm text-gray-200 hover:text-blue-400 transition"
          >
            FAQ
          </Link>
        ) : null}

        {!isHome && user && (
          <div className="flex items-center gap-6 text-sm">

            <Link href="/dashboard" className="hover:text-blue-400">
              Dashboard
            </Link>


            {/* DROPDOWN FUNCTION */}
            {[
              {
                key: "trades",
                label: "Trades",
                items: [
                  { label: "Input Trade", link: "/app" },
                  { label: "Trade History", link: "/trades" },
                ],
              },
              {
                key: "analytics",
                label: "Analytics",
                items: [
                  { label: "Calendar", link: "/calendar" },
                  profile?.is_pro
                    ? { label: "AI Analyst", link: "/analyst", highlight: true }
                    : { label: "AI Analyst 🔒", link: null },
                ],
              },
              {
                key: "community",
                label: "Community",
                items: [
                  { label: "My Profile", action: () => router.push(`/profile/${profile?.id}`) },
                   { label: "Feed", action: () => router.push("/feed") },
                  {
                    label: "Messages",
                    action: () => router.push("/messages"),
                    badge: unreadMessagesCount,
                  },
                  { label: "Leaderboard", action: () => router.push("/leaderboard") },
                  { label: "Global Chat", action: () => router.push("/chat") },
                  { label: "Explore", action: () => router.push("/explore") },
                ],
              },
              {
                key: "earnings",
                label: "Earnings",
                items: [
                  { label: "Affiliate Dashboard", link: "/affiliate", highlight: true },
                  { label: "Referral Stats", link: "/affiliate/referrals" },
                  { label: "Payouts (Soon)", link: null },
                ],
              },
            ].map((menu) => (
              <div key={menu.key} className="relative">
                <button
                  onClick={() => toggleMenu(menu.key)}
                  className="hover:text-blue-400"
                >
                  {menu.label} ▾
                </button>

                {activeMenu === menu.key && (
                  <div className="absolute top-full mt-2 w-56 bg-[#1e293b] border border-white/10 rounded shadow-lg z-[9999]">

                    {menu.items.map((item, i) => (
                      <div key={i}>
                        {item.link ? (
                          <Link
                            href={item.link}
                            className={`block px-4 py-2 hover:bg-white/10 ${
                              item.highlight ? "text-emerald-400 font-semibold" : ""
                            }`}
                          >
                            {item.label}
                          </Link>
                        ) : item.action ? (
                          <button
                            onClick={item.action}
                            className="flex justify-between w-full px-4 py-2 hover:bg-white/10 text-left"
                          >
                            {item.label}
                            {item.badge > 0 && (
                              <span className="bg-red-500 text-xs px-2 rounded-full">
                                {item.badge}
                              </span>
                            )}
                          </button>
                        ) : (
                          <div className="px-4 py-2 text-gray-400">
                            {item.label}
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* RIGHT */}
      {!user ? (
        <button onClick={() => router.push("/login")} className="border px-4 py-2 rounded shrink-0">
          Login
        </button>
      ) : (
        <div className="flex items-center gap-3 shrink-0">
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
            {unreadCount > 0 && (
              <span className="absolute -top-1 -right-2 bg-red-500 text-white text-xs px-1.5 py-0.5 rounded-full tabular-nums min-w-[1.25rem] text-center">
                {unreadCount > 9 ? "9+" : unreadCount}
              </span>
            )}
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
      )}
    </div>
  )
}