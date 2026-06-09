"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { useUserProfile } from "@/lib/useUserProfile"
import Navbar from "./Navbar"

export default function PublicNavbar() {
  const { user } = useUserProfile()
  const pathname = usePathname()
  const isActive = (path: string) => pathname === path

  if (user) {
    return <Navbar />
  }

  return (
    <div className="fixed top-0 left-0 z-[9999] w-full overflow-visible text-white">
      <div className="flex h-16 w-full shrink-0 items-center border-b border-white/5 bg-[#0b1f3a]">
        <div className="flex h-full w-full items-center justify-between px-4 md:px-6">
          <div className="flex min-w-0 items-center gap-2 whitespace-nowrap sm:gap-3">
            <Link
              href="/"
              className="shrink-0 whitespace-nowrap bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-lg font-bold text-transparent"
            >
              TradeTraxs
            </Link>
            <Link
              href="/faq"
              className={`shrink-0 rounded px-2 py-1 text-sm transition ${
                isActive("/faq")
                  ? "bg-blue-500/20 text-blue-300"
                  : "text-gray-300 hover:text-white"
              }`}
            >
              FAQ
            </Link>
            <Link
              href="/pricing"
              className={`shrink-0 rounded px-2 py-1 text-sm transition ${
                isActive("/pricing")
                  ? "bg-blue-500/20 text-blue-300"
                  : "text-gray-300 hover:text-white"
              }`}
            >
              Pricing
            </Link>
          </div>

          <div className="flex shrink-0 items-center whitespace-nowrap">
            <Link
              href="/login"
              className="rounded bg-blue-500 px-4 py-1.5 text-sm font-medium text-white transition hover:bg-blue-600"
            >
              Login
            </Link>
          </div>
        </div>
      </div>
    </div>
  )
}
