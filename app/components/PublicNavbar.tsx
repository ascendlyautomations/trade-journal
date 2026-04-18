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
            className="whitespace-nowrap text-sm font-medium transition hover:text-blue-400"
          >
            FAQ
          </Link>

          <Link
            href="/pricing"
            className="whitespace-nowrap text-sm font-medium transition hover:text-blue-400"
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
                className="hidden rounded border px-2 py-1 text-sm font-medium whitespace-nowrap md:inline"
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
            <Link href="/dashboard" onClick={closeMenu} className="text-white hover:text-blue-400">
              Dashboard
            </Link>
            <Link href="/input-trade" onClick={closeMenu} className="text-white hover:text-blue-400">
              Input Trade
            </Link>

            <div className="my-2 border-t border-white/10" />

            <div className="font-medium text-white">Analytics</div>
            <div className="flex flex-col gap-1 pl-3 text-gray-400">
              <Link href="/trade-history" onClick={closeMenu} className="hover:text-white">
                Trade History
              </Link>
              <Link href="/backtest" onClick={closeMenu} className="hover:text-white">
                Backtest Stats
              </Link>
              <Link href="/calendar" onClick={closeMenu} className="hover:text-white">
                Calendar
              </Link>
              {isProActive(profile) ? (
                <Link href="/ai" onClick={closeMenu} className="hover:text-white">
                  AI Analysis
                </Link>
              ) : (
                <span className="text-gray-500">AI Analysis 🔒</span>
              )}
            </div>

            <div className="my-2 border-t border-white/10" />

            <div className="font-medium text-white">Community</div>
            <div className="flex flex-col gap-1 pl-3 text-gray-400">
              <Link href="/feed" onClick={closeMenu} className="hover:text-white">
                Feed
              </Link>
              <Link href="/trade-rooms" onClick={closeMenu} className="hover:text-white">
                Trade Rooms
              </Link>
              <Link href="/leaderboard" onClick={closeMenu} className="hover:text-white">
                Leaderboard
              </Link>
              <Link href="/explore" onClick={closeMenu} className="hover:text-white">
                Explore
              </Link>
            </div>

            <div className="my-2 border-t border-white/10" />

            <div className="font-medium text-white">Affiliate</div>
            <div className="flex flex-col gap-1 pl-3 text-gray-400">
              <Link href="/affiliate" onClick={closeMenu} className="hover:text-white">
                Affiliate Dashboard
              </Link>
              <Link href="/payouts" onClick={closeMenu} className="hover:text-white">
                Payouts
              </Link>
            </div>

            <div className="my-2 border-t border-white/10" />

            {profile?.id ? (
              <Link
                href={`/profile/${profile.id}`}
                onClick={closeMenu}
                className="text-white hover:text-blue-400"
              >
                Profile
              </Link>
            ) : (
              <span className="text-gray-500">Profile</span>
            )}
            <Link href="/messages" onClick={closeMenu} className="text-white hover:text-blue-400">
              Messages
            </Link>
          </div>
        </div>
      ) : null}
    </div>
  )
}
