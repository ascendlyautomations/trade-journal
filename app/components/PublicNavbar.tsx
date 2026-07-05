"use client"

import IntentPrefetchLink from "@/lib/IntentPrefetchLink"
import { usePathname, useRouter } from "next/navigation"
import { useEffect, useState } from "react"
import { useUserProfile } from "@/lib/useUserProfile"
import { isAuthRoute } from "@/lib/authRoutes"
import { shouldShowMarketingNavbar } from "@/lib/marketingAccess"
import { hasActiveMembership } from "@/lib/subscriptionAccess"
import { isDemoUserId } from "@/lib/demo/constants"
import { NAVBAR_BRAND_LINK_CLASS_NOWRAP } from "@/lib/navbarBrand"

const DESKTOP_NAV_LINKS = [
  { href: "/faq", label: "FAQ" },
  { href: "/pricing", label: "Pricing" },
  { href: "/affiliate", label: "Affiliate" },
  { href: "/contact", label: "Contact" },
  { href: "/legal", label: "Legal" },
  { href: "/about", label: "About" },
] as const

const MOBILE_NAV_LINKS = [
  { href: "/faq", label: "FAQ" },
  { href: "/pricing", label: "Pricing" },
  { href: "/affiliate", label: "Affiliate" },
  { href: "/contact", label: "Contact" },
  { href: "/legal", label: "Legal" },
  { href: "/about", label: "About" },
] as const

function isNavLinkActive(pathname: string, href: string): boolean {
  if (href === "/affiliate") {
    return pathname === "/affiliate"
  }
  return pathname === href
}

function navLinkClass(pathname: string, href: string): string {
  return `shrink-0 rounded px-2 py-1 text-sm transition ${
    isNavLinkActive(pathname, href)
      ? "bg-blue-500/20 text-blue-300"
      : "text-gray-300 hover:text-white"
  }`
}

function mobileNavLinkClass(pathname: string, href: string): string {
  return `rounded-lg px-3 py-2 transition ${
    isNavLinkActive(pathname, href)
      ? "bg-blue-500/20 text-blue-300"
      : "text-gray-300 hover:text-white"
  }`
}

/** Logged-out marketing navbar — never shown during auth/onboarding/app flow. */
export default function PublicNavbar() {
  const { user, profile, loading } = useUserProfile()
  const pathname = usePathname()
  const router = useRouter()
  const [menuOpen, setMenuOpen] = useState(false)

  const isAuthenticatedUser = !!user && !isDemoUserId(user.id)
  const showCustomerHomeChrome =
    !isAuthRoute(pathname) &&
    isAuthenticatedUser &&
    !loading &&
    !!profile &&
    hasActiveMembership(profile)

  useEffect(() => {
    setMenuOpen(false)
  }, [pathname])

  if (isAuthRoute(pathname)) {
    return null
  }

  if (showCustomerHomeChrome) {
    return (
      <div className="fixed left-0 top-0 z-[9999] w-full overflow-visible text-white">
        <div className="flex h-16 w-full shrink-0 items-center border-b border-white/5 bg-[#0b1f3a]">
          <div className="flex h-full w-full items-center justify-between px-4 md:px-6">
            <IntentPrefetchLink
              href="/"
              className={NAVBAR_BRAND_LINK_CLASS_NOWRAP}
            >
              TradeTraxs
            </IntentPrefetchLink>
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

  return (
    <div className="fixed left-0 top-0 z-[9999] w-full overflow-visible text-white">
      <div className="flex h-16 w-full shrink-0 items-center border-b border-white/5 bg-[#0b1f3a]">
        <div className="flex h-full w-full items-center justify-between px-4 md:px-6">
          <div className="flex min-w-0 items-center gap-2 whitespace-nowrap sm:gap-3">
            <IntentPrefetchLink
              href="/"
              className={NAVBAR_BRAND_LINK_CLASS_NOWRAP}
            >
              TradeTraxs
            </IntentPrefetchLink>
            <nav
              className="hidden min-w-0 items-center gap-2 sm:gap-3 md:flex"
              aria-label="Marketing"
            >
              {DESKTOP_NAV_LINKS.map((link) => (
                <IntentPrefetchLink
                  key={link.href}
                  href={link.href}
                  className={navLinkClass(pathname, link.href)}
                >
                  {link.label}
                </IntentPrefetchLink>
              ))}
            </nav>
          </div>

          <div className="flex shrink-0 items-center gap-2 whitespace-nowrap sm:gap-3">
            <div className="hidden items-center gap-2 sm:gap-3 md:flex">
              <IntentPrefetchLink
                href="/login"
                className="rounded border border-white/20 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-white/10 sm:px-4"
              >
                Login
              </IntentPrefetchLink>
              <IntentPrefetchLink
                href="/login?tab=signup"
                className="rounded bg-blue-500 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-blue-600 sm:px-4"
              >
                Sign Up
              </IntentPrefetchLink>
            </div>

            <div className="flex items-center gap-2 md:hidden">
              <IntentPrefetchLink
                href="/login"
                className="rounded border border-white/20 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-white/10"
              >
                Login
              </IntentPrefetchLink>
              <button
                type="button"
                className="px-1 py-1 text-2xl leading-none text-white"
                aria-expanded={menuOpen}
                aria-label={menuOpen ? "Close menu" : "Open menu"}
                onClick={() => setMenuOpen((open) => !open)}
              >
                ☰
              </button>
            </div>
          </div>
        </div>
      </div>

      {menuOpen ? (
        <div className="max-h-[calc(100vh-4rem)] w-full overflow-y-auto border-t border-white/5 bg-[#0b1f3a] md:hidden">
          <nav
            className="flex w-full flex-col gap-2 px-4 pb-3 pt-1.5 text-sm text-white md:px-6"
            aria-label="Marketing menu"
          >
            <IntentPrefetchLink
              href="/login?tab=signup"
              className="rounded-lg px-3 py-2 font-semibold text-gray-200 transition hover:text-white"
              onClick={() => setMenuOpen(false)}
            >
              Sign Up
            </IntentPrefetchLink>
            <IntentPrefetchLink
              href="/login"
              className="rounded-lg px-3 py-2 font-semibold text-gray-200 transition hover:text-white"
              onClick={() => setMenuOpen(false)}
            >
              Login
            </IntentPrefetchLink>
            <div className="my-1 border-t border-white/10" aria-hidden />
            {MOBILE_NAV_LINKS.map((link) => (
              <IntentPrefetchLink
                key={link.href}
                href={link.href}
                className={mobileNavLinkClass(pathname, link.href)}
                onClick={() => setMenuOpen(false)}
              >
                {link.label}
              </IntentPrefetchLink>
            ))}
          </nav>
        </div>
      ) : null}
    </div>
  )
}
