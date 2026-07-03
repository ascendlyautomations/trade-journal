"use client"

import Link from "next/link"
import { usePathname, useRouter } from "next/navigation"
import { useUserProfile } from "@/lib/useUserProfile"
import { shouldShowMarketingNavbar } from "@/lib/marketingAccess"
import { hasActiveMembership } from "@/lib/subscriptionAccess"
import { isDemoUserId } from "@/lib/demo/constants"

/** Logged-out marketing navbar — never shown during auth/onboarding/app flow. */
export default function PublicNavbar() {
  const { user, profile, loading } = useUserProfile()
  const pathname = usePathname()
  const router = useRouter()

  const isAuthenticatedUser = !!user && !isDemoUserId(user.id)
  const showCustomerHomeChrome =
    isAuthenticatedUser &&
    !loading &&
    !!profile &&
    hasActiveMembership(profile)

  if (showCustomerHomeChrome) {
    return (
      <div className="fixed left-0 top-0 z-[9999] w-full overflow-visible text-white">
        <div className="flex h-16 w-full shrink-0 items-center border-b border-white/5 bg-[#0b1f3a]">
          <div className="flex h-full w-full items-center justify-between px-4 md:px-6">
            <Link
              href="/"
              className="shrink-0 whitespace-nowrap bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-lg font-bold text-transparent"
            >
              TradeTraxs
            </Link>
            <button
              type="button"
              onClick={() => router.push("/dashboard")}
              className="rounded bg-blue-500 px-4 py-1.5 text-sm font-medium text-white transition hover:bg-blue-600"
            >
              Return to App
            </button>
          </div>
        </div>
      </div>
    )
  }

  if (!shouldShowMarketingNavbar(pathname, user, profile, loading)) {
    return null
  }

  const isActive = (path: string) => pathname === path

  return (
    <div className="fixed left-0 top-0 z-[9999] w-full overflow-visible text-white">
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

          <div className="flex shrink-0 items-center gap-2 whitespace-nowrap sm:gap-3">
            <Link
              href="/login"
              className="rounded border border-white/20 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-white/10 sm:px-4"
            >
              Login
            </Link>
            <Link
              href="/login?tab=signup"
              className="rounded bg-blue-500 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-blue-600 sm:px-4"
            >
              Sign Up
            </Link>
          </div>
        </div>
      </div>
    </div>
  )
}
