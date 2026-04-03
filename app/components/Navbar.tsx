"use client"

import Link from "next/link"
import { useEffect, useState, useRef } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter, usePathname } from "next/navigation"
import { useUserProfile } from "../../lib/useUserProfile"

export default function Navbar() {
  const { user, profile, loading } = useUserProfile()

  const [activeMenu, setActiveMenu] = useState<string | null>(null)
  const [unreadCount, setUnreadCount] = useState(0)

  const router = useRouter()
  const pathname = usePathname()
  const isHome = pathname === "/"

  const navRef = useRef<HTMLDivElement>(null)

  // CLOSE ON OUTSIDE CLICK
  useEffect(() => {
    function handleClickOutside(e: any) {
      if (navRef.current && !navRef.current.contains(e.target)) {
        setActiveMenu(null)
      }
    }

    document.addEventListener("mousedown", handleClickOutside)
    return () => document.removeEventListener("mousedown", handleClickOutside)
  }, [])

  useEffect(() => {
    if (user) fetchUnread()
  }, [user])

  async function fetchUnread() {
    const { count } = await supabase
      .from("direct_messages")
      .select("*", { count: "exact", head: true })
      .eq("recipient_id", user.id)
      .eq("is_read", false)

    setUnreadCount(count ?? 0)
  }

  function toggleMenu(menu: string) {
    setActiveMenu(activeMenu === menu ? null : menu)
  }

  if (loading) return null

  return (
    <div
      ref={navRef}
      className="w-full px-6 py-3 border-b border-white/10 flex justify-between items-center bg-[#0f172a] text-gray-100 relative z-[9999]"
    >
      {/* LEFT */}
      <div className="flex items-center gap-8">

        <Link href="/" className="font-bold text-xl bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
          TradeTraxs
        </Link>

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
                   { label: "Feed", action: () => router.push(`/feed/${profile?.id}`) },
                  {
                    label: "Messages",
                    action: () => router.push("/messages"),
                    badge: unreadCount,
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
      <div className="relative">
        {!user ? (
          <button onClick={() => router.push("/login")} className="border px-4 py-2 rounded">
            Login
          </button>
        ) : (
          <div className="relative">

            <button
              onClick={() => toggleMenu("account")}
              className="flex items-center gap-2 border px-3 py-1 rounded"
            >
              {profile?.avatar_url ? (
                <img src={profile.avatar_url} className="w-6 h-6 rounded-full" />
              ) : (
                <div className="w-6 h-6 rounded-full bg-gray-500" />
              )}
              <span>{profile?.name || profile?.username}</span>
            </button>

            {activeMenu === "account" && (
              <div className="absolute right-0 mt-2 w-48 bg-[#1e293b] border border-white/10 rounded shadow-lg z-[9999]">

                <button onClick={() => router.push("/settings")} className="px-4 py-2 hover:bg-white/10 w-full text-left">
                  Settings
                </button>

                <button
                  onClick={async () => {
                    await supabase.auth.signOut()
                    router.push("/")
                  }}
                  className="px-4 py-2 text-red-400 hover:bg-red-500/10 w-full text-left"
                >
                  Sign Out
                </button>

              </div>
            )}

          </div>
        )}
      </div>
    </div>
  )
}