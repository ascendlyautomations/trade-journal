"use client"

import Link from "next/link"
import { useEffect, useState, useRef } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter, usePathname } from "next/navigation"
import { useUserProfile } from "../../lib/useUserProfile" // 🔥 NEW

export default function Navbar() {
  const { user, profile, loading } = useUserProfile() // 🔥 GLOBAL PROFILE

  const [open, setOpen] = useState(false)
  const [socialOpen, setSocialOpen] = useState(false)
  const [unreadCount, setUnreadCount] = useState(0)

  const router = useRouter()
  const pathname = usePathname()
  const isHome = pathname === "/"

  const dropdownRef = useRef<HTMLDivElement>(null)
  const socialRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (user) {
      fetchUnread()
      setupRealtime()
    }
  }, [user])

  useEffect(() => {
    function handleClickOutside(e: any) {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target)) {
        setOpen(false)
      }
      if (socialRef.current && !socialRef.current.contains(e.target)) {
        setSocialOpen(false)
      }
    }

    document.addEventListener("mousedown", handleClickOutside)
    return () => document.removeEventListener("mousedown", handleClickOutside)
  }, [])

  async function fetchUnread() {
    if (!user) return

    const { count } = await supabase
      .from("direct_messages")
      .select("*", { count: "exact", head: true })
      .eq("recipient_id", user.id)
      .eq("is_read", false)

    setUnreadCount(count ?? 0)
  }

  function setupRealtime() {
    const channel = supabase
      .channel("navbar-unread")
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "direct_messages"
        },
        () => {
          fetchUnread()
        }
      )
      .subscribe()

    return () => supabase.removeChannel(channel)
  }

  async function handleLogout() {
    await supabase.auth.signOut()
    router.push("/")
  }

  if (loading) return null

  return (
    <div className="w-full p-4 border-b border-white/10 flex justify-between items-center bg-[#0f172a] text-gray-100">

      {/* LEFT */}
      <div className="flex gap-6 items-center">

        <Link href="/" className="font-bold text-xl bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
          TradeTrackas
        </Link>

        {!isHome && user && (
          <>
            <Link href="/app">Input Trade</Link>
            <Link href="/trades">Trade History</Link>
            <Link href="/dashboard">Dashboard</Link>
            <Link href="/calendar">Calendar</Link>

            {/* 🔥 SOCIAL DROPDOWN */}
            <div className="relative" ref={socialRef}>
              <button onClick={() => setSocialOpen(!socialOpen)}>
                Social ▾
              </button>

              {socialOpen && (
                <div className="absolute mt-2 w-56 bg-[#1e293b] border border-white/10 rounded shadow-lg flex flex-col z-50">

                  {profile?.id && (
                    <button
                      onClick={() => router.push(`/profile/${profile.id}`)}
                      className="px-4 py-2 hover:bg-white/10 text-left text-blue-300 font-semibold"
                    >
                      My Profile
                    </button>
                  )}

                  <div className="border-t border-white/10 my-1" />

                  <button onClick={() => router.push("/messages")} className="px-4 py-2 hover:bg-white/10 text-left">
                    Messages
                  </button>

                  <button onClick={() => router.push("/leaderboard")} className="px-4 py-2 hover:bg-white/10 text-left">
                    Leaderboard
                  </button>

                  <button onClick={() => router.push("/chat")} className="px-4 py-2 hover:bg-white/10 text-left">
                    Global Chat
                  </button>

                  <button onClick={() => router.push("/explore")} className="px-4 py-2 hover:bg-white/10 text-left">
                    Explore
                  </button>

                  <button onClick={() => router.push("/search")} className="px-4 py-2 hover:bg-white/10 text-left">
                    Search Users
                  </button>

                </div>
              )}
            </div>

            {/* 🔥 MESSAGES BADGE */}
            <div className="relative cursor-pointer" onClick={() => router.push("/messages")}>

              <span>Messages</span>

              {unreadCount > 0 && (
                <span className="absolute -top-2 -right-4 bg-red-500 text-xs px-2 py-[2px] rounded-full">
                  {unreadCount}
                </span>
              )}

            </div>

            <Link href="/analyst">AI Analyst</Link>
            <Link href="/settings">Settings</Link>
          </>
        )}

      </div>

      {/* RIGHT */}
      <div className="relative" ref={dropdownRef}>

        {!user ? (
          <button onClick={() => router.push("/login")} className="border px-4 py-2 rounded">
            Login
          </button>
        ) : (
          <>
            <button onClick={() => setOpen(!open)} className="border px-3 py-1 rounded">

              {/* 🔥 AVATAR NOW GLOBAL + INSTANT */}
              <div className="flex items-center gap-2">
                {profile?.avatar_url ? (
                  <img
                    src={profile.avatar_url}
                    className="w-6 h-6 rounded-full object-cover"
                  />
                ) : (
                  <div className="w-6 h-6 rounded-full bg-gray-500" />
                )}
                <span>{profile?.name || profile?.username}</span>
              </div>

            </button>

            {open && (
              <div className="absolute right-0 mt-2 w-48 bg-[#1e293b] border border-white/10 rounded shadow-lg flex flex-col">

                <button onClick={() => router.push("/settings")} className="px-4 py-2 hover:bg-white/10 text-left">
                  Settings
                </button>

                <button onClick={handleLogout} className="px-4 py-2 text-red-400 hover:bg-red-500/10 text-left">
                  Sign Out
                </button>

              </div>
            )}
          </>
        )}

      </div>

    </div>
  )
}