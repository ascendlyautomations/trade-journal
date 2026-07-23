"use client"

import IntentPrefetchLink from "@/lib/IntentPrefetchLink"
import { usePathname, useRouter } from "next/navigation"
import { useEffect, useState, type MouseEvent } from "react"
import { useUserProfile } from "@/lib/useUserProfile"
import { isAuthRoute } from "@/lib/authRoutes"
import {
  shouldShowCustomerHomeChrome,
  shouldShowMarketingNavbar,
} from "@/lib/marketingAccess"
import { NAVBAR_BRAND_LINK_CLASS_NOWRAP } from "@/lib/navbarBrand"
import { navigateToComingSoonSection } from "@/app/components/landing/LandingComingSoonSection"

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

const COMING_SOON_NAV_HREF = "/#coming-soon"

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

function comingSoonNavClass(active: boolean, mobile: boolean): string {
  if (mobile) {
    return `rounded-lg px-3 py-2 transition ${
      active
        ? "bg-blue-500/20 text-blue-300"
        : "text-gray-300 hover:text-white"
    }`
  }
  return `shrink-0 rounded px-2 py-1 text-sm transition ${
    active
      ? "bg-blue-500/20 text-blue-300"
      : "text-gray-300 hover:text-white"
  }`
}

/** Marketing navbar — logged-out visitors and completed members on public pages. */
export default function PublicNavbar() {
  const { user, profile, loading } = useUserProfile()
  const pathname = usePathname()
  const router = useRouter()
  const [menuOpen, setMenuOpen] = useState(false)
  const [comingSoonActive, setComingSoonActive] = useState(false)

  const showReturnToApp = shouldShowCustomerHomeChrome(user, profile, loading)

  useEffect(() => {
    setMenuOpen(false)
  }, [pathname])

  useEffect(() => {
    function syncComingSoonActive() {
      setComingSoonActive(
        pathname === "/" && window.location.hash === "#coming-soon"
      )
    }
    syncComingSoonActive()
    window.addEventListener("hashchange", syncComingSoonActive)
    return () => window.removeEventListener("hashchange", syncComingSoonActive)
  }, [pathname])

  if (isAuthRoute(pathname)) {
    return null
  }

  if (!shouldShowMarketingNavbar(pathname, user, profile, loading)) {
    return null
  }

  function handleReturnToApp() {
    setMenuOpen(false)
    router.push("/dashboard")
  }

  function handleComingSoonClick(event: MouseEvent<HTMLAnchorElement>) {
    event.preventDefault()
    setMenuOpen(false)
    setComingSoonActive(true)
    navigateToComingSoonSection()
  }

  function renderNavLinks(mobile: boolean) {
    const links = mobile ? MOBILE_NAV_LINKS : DESKTOP_NAV_LINKS
    const classFor = mobile ? mobileNavLinkClass : navLinkClass

    return links.flatMap((link) => {
      const item = (
        <IntentPrefetchLink
          key={link.href}
          href={link.href}
          className={classFor(pathname, link.href)}
          onClick={mobile ? () => setMenuOpen(false) : undefined}
        >
          {link.label}
        </IntentPrefetchLink>
      )

      if (link.href !== "/about") return [item]

      return [
        item,
        <a
          key={COMING_SOON_NAV_HREF}
          href={COMING_SOON_NAV_HREF}
          className={comingSoonNavClass(comingSoonActive, mobile)}
          onClick={handleComingSoonClick}
        >
          Coming Soon
        </a>,
      ]
    })
  }

  return (
    <div className="fixed left-0 top-0 z-[9999] w-full overflow-visible bg-[#0b1f3a] pt-[var(--safe-area-top)] text-white">
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
              {renderNavLinks(false)}
            </nav>
          </div>

          <div className="flex shrink-0 items-center gap-2 whitespace-nowrap sm:gap-3">
            {showReturnToApp ? (
              <button
                type="button"
                onClick={handleReturnToApp}
                className="hidden rounded bg-blue-500 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-blue-600 sm:px-4 md:inline-flex"
              >
                Return to App
              </button>
            ) : (
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
            )}

            <div className="flex items-center gap-2 md:hidden">
              {!showReturnToApp ? (
                <IntentPrefetchLink
                  href="/login"
                  className="rounded border border-white/20 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-white/10"
                >
                  Login
                </IntentPrefetchLink>
              ) : null}
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
        <div className="max-h-[calc(100dvh-var(--app-header-offset))] w-full overflow-y-auto overscroll-y-contain border-t border-white/5 bg-[#0b1f3a] md:hidden">
          <nav
            className="flex w-full flex-col gap-2 px-4 pb-[calc(0.75rem+var(--safe-area-bottom))] pt-1.5 text-sm text-white md:px-6"
            aria-label="Marketing menu"
          >
            {showReturnToApp ? (
              <>
                <button
                  type="button"
                  onClick={handleReturnToApp}
                  className="rounded-lg px-3 py-2 text-left font-semibold text-gray-200 transition hover:text-white"
                >
                  Return to App
                </button>
                <div className="my-1 border-t border-white/10" aria-hidden />
              </>
            ) : (
              <>
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
              </>
            )}
            {renderNavLinks(true)}
          </nav>
        </div>
      ) : null}
    </div>
  )
}
