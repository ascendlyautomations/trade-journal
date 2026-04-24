"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import { usePathname } from "next/navigation"
import { useUserProfile } from "@/lib/useUserProfile"
import { isProActive } from "@/lib/subscription"

export default function PublicNavbar() {
  const { user, profile } = useUserProfile()
  const [menuOpen, setMenuOpen] = useState(false)
  const pathname = usePathname()

  useEffect(() => {
    setMenuOpen(false)
  }, [pathname])

  const closeMenu = () => setMenuOpen(false)
  const isActive = (path: string) => pathname === path
  const isGroupActive = (paths: string[]) =>
    paths.some((p) => pathname.startsWith(p))

  return (
    <div className="fixed top-0 left-0 z-[9999] w-full overflow-visible text-white">
      <div className="flex h-16 w-full shrink-0 items-center border-b border-white/5 bg-[#0b1f3a]">
        <div className="flex h-full w-full items-center justify-between px-4 md:px-6">
        <div className="flex items-center gap-6 whitespace-nowrap">
          <Link
            href="/"
            className="whitespace-nowrap bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-lg font-bold text-transparent"
          >
            TradeTraxs
          </Link>

          <Link
            href="/faq"
            className={`whitespace-nowrap px-3 py-1 rounded transition ${
              isActive("/faq")
                ? "bg-blue-500/20 text-blue-300"
                : "text-gray-300 hover:text-white"
            }`}
          >
            FAQ
          </Link>

          <Link
            href="/pricing"
            className={`whitespace-nowrap px-3 py-1 rounded transition ${
              isActive("/pricing")
                ? "bg-blue-500/20 text-blue-300"
                : "text-gray-300 hover:text-white"
            }`}
          >
            Pricing
          </Link>
        </div>

        <div className="flex shrink-0 items-center gap-4 whitespace-nowrap">
          {!user && (
            <Link
              href="/login"
              className="whitespace-nowrap rounded bg-blue-500 px-4 py-1 text-sm font-medium"
            >
              Login
            </Link>
          )}

          {user ? (
            <>
              <Link
                href="/dashboard"
                className={`hidden px-3 py-1 rounded transition whitespace-nowrap md:inline ${
                  isActive("/dashboard")
                    ? "bg-blue-500/20 text-blue-300"
                    : "text-gray-300 hover:text-white"
                }`}
              >
                Dashboard
              </Link>

              <button
                type="button"
                aria-expanded={menuOpen}
                aria-label={menuOpen ? "Close menu" : "Open menu"}
                onClick={() => setMenuOpen((o) => !o)}
                className="ml-3 text-2xl text-white md:hidden"
              >
                ☰
              </button>
            </>
          ) : null}
        </div>
        </div>
      </div>

      {menuOpen && user ? (
        <div className="absolute left-0 top-full z-50 w-full border-t border-white/5 bg-[#0b1f3a] md:hidden">
          <div className="flex w-full flex-col gap-3 px-4 py-4 text-sm md:px-6">
            <Link
              href="/dashboard"
              onClick={closeMenu}
              className={`px-3 py-1 rounded transition ${
                isActive("/dashboard")
                  ? "bg-blue-500/20 text-blue-300"
                  : "text-gray-300 hover:text-white"
              }`}
            >
              Dashboard
            </Link>
            <Link
              href="/app"
              onClick={closeMenu}
              className={`px-3 py-1 rounded transition ${
                isActive("/app")
                  ? "bg-blue-500/20 text-blue-300"
                  : "text-gray-300 hover:text-white"
              }`}
            >
              Input Trade
            </Link>

            <div className="my-2 border-t border-white/10" />

            <div
              className={`font-medium px-3 py-1 rounded transition ${
                isGroupActive(["/analytics", "/analyst"])
                  ? "bg-blue-500/20 text-blue-300"
                  : "text-gray-300 hover:text-white"
              }`}
            >
              Analytics
            </div>
            <div className="flex flex-col gap-1 pl-3 text-gray-400">
              <Link
                href="/trades"
                onClick={closeMenu}
                className={`block px-3 py-2 rounded ${
                  isActive("/trades")
                    ? "bg-blue-500/20 text-blue-300"
                    : "hover:bg-white/10 text-gray-300"
                }`}
              >
                Trade History
              </Link>
              <Link
                href="/backtest"
                onClick={closeMenu}
                className={`block px-3 py-2 rounded ${
                  isActive("/backtest")
                    ? "bg-blue-500/20 text-blue-300"
                    : "hover:bg-white/10 text-gray-300"
                }`}
              >
                Backtest Stats
              </Link>
              <Link
                href="/calendar"
                onClick={closeMenu}
                className={`block px-3 py-2 rounded ${
                  isActive("/calendar")
                    ? "bg-blue-500/20 text-blue-300"
                    : "hover:bg-white/10 text-gray-300"
                }`}
              >
                Calendar
              </Link>
              {isProActive(profile) ? (
                <Link
                  href="/analyst"
                  onClick={closeMenu}
                  className={`block px-3 py-2 rounded ${
                    isActive("/analyst")
                      ? "bg-blue-500/20 text-blue-300"
                      : "hover:bg-white/10 text-gray-300"
                  }`}
                >
                  AI Analysis
                </Link>
              ) : (
                <span className="text-gray-500">AI Analysis 🔒</span>
              )}
            </div>

            <div className="my-2 border-t border-white/10" />

            <div
              className={`font-medium px-3 py-1 rounded transition ${
                isGroupActive(["/community", "/feed", "/trade-rooms", "/leaderboard", "/explore"])
                  ? "bg-blue-500/20 text-blue-300"
                  : "text-gray-300 hover:text-white"
              }`}
            >
              Community
            </div>
            <div className="flex flex-col gap-1 pl-3 text-gray-400">
              <Link
                href="/feed"
                onClick={closeMenu}
                className={`block px-3 py-2 rounded ${
                  isActive("/feed")
                    ? "bg-blue-500/20 text-blue-300"
                    : "hover:bg-white/10 text-gray-300"
                }`}
              >
                Feed
              </Link>
              <Link
                href="/trade-rooms"
                onClick={closeMenu}
                className={`block px-3 py-2 rounded ${
                  isActive("/trade-rooms")
                    ? "bg-blue-500/20 text-blue-300"
                    : "hover:bg-white/10 text-gray-300"
                }`}
              >
                Trade Rooms
              </Link>
              <Link
                href="/leaderboard"
                onClick={closeMenu}
                className={`block px-3 py-2 rounded ${
                  isActive("/leaderboard")
                    ? "bg-blue-500/20 text-blue-300"
                    : "hover:bg-white/10 text-gray-300"
                }`}
              >
                Leaderboard
              </Link>
              <Link
                href="/explore"
                onClick={closeMenu}
                className={`block px-3 py-2 rounded ${
                  isActive("/explore")
                    ? "bg-blue-500/20 text-blue-300"
                    : "hover:bg-white/10 text-gray-300"
                }`}
              >
                Explore
              </Link>
            </div>

            <div className="my-2 border-t border-white/10" />

            <div
              className={`font-medium px-3 py-1 rounded transition ${
                isGroupActive(["/affiliate", "/payouts"])
                  ? "bg-blue-500/20 text-blue-300"
                  : "text-gray-300 hover:text-white"
              }`}
            >
              Affiliate
            </div>
            <div className="flex flex-col gap-1 pl-3 text-gray-400">
              <Link
                href="/affiliate"
                onClick={closeMenu}
                className={`block px-3 py-2 rounded ${
                  isActive("/affiliate")
                    ? "bg-blue-500/20 text-blue-300"
                    : "hover:bg-white/10 text-gray-300"
                }`}
              >
                Affiliate Dashboard
              </Link>
              <Link
                href="/payouts"
                onClick={closeMenu}
                className={`block px-3 py-2 rounded ${
                  isActive("/payouts")
                    ? "bg-blue-500/20 text-blue-300"
                    : "hover:bg-white/10 text-gray-300"
                }`}
              >
                Payouts
              </Link>
            </div>

            <div className="my-2 border-t border-white/10" />

            {profile?.id ? (
              <Link
                href={`/profile/${profile.id}`}
                onClick={closeMenu}
                className={`px-3 py-1 rounded transition ${
                  isGroupActive(["/profile"])
                    ? "bg-blue-500/20 text-blue-300"
                    : "text-gray-300 hover:text-white"
                }`}
              >
                Profile
              </Link>
            ) : (
              <span className="text-gray-500">Profile</span>
            )}
            <Link
              href="/messages"
              onClick={closeMenu}
              className={`px-3 py-1 rounded transition ${
                isActive("/messages")
                  ? "bg-blue-500/20 text-blue-300"
                  : "text-gray-300 hover:text-white"
              }`}
            >
              Messages
            </Link>
          </div>
        </div>
      ) : null}
    </div>
  )
}
