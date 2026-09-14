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
import {
  NAV_CHROME_BAR_SUBTLE_BORDER,
  NAV_CHROME_FIXED_ROOT,
  NAV_CTA_PRIMARY,
  NAV_DIVIDER,
  NAV_ITEM_ACTIVE,
  NAV_ITEM_INACTIVE,
  NAV_LINK_SECONDARY_HOVER_ACCENT,
  NAV_PUBLIC_MOBILE_MENU,
} from "@/lib/navChromeStyles"

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
    isNavLinkActive(pathname, href) ? NAV_ITEM_ACTIVE : NAV_ITEM_INACTIVE
  }`
}

function mobileNavLinkClass(pathname: string, href: string): string {
  return `rounded-lg px-3 py-2 transition ${
    isNavLinkActive(pathname, href) ? NAV_ITEM_ACTIVE : NAV_ITEM_INACTIVE
  }`
}

function comingSoonNavClass(active: boolean, mobile: boolean): string {
  if (mobile) {
    return `rounded-lg px-3 py-2 transition ${
      active ? NAV_ITEM_ACTIVE : NAV_ITEM_INACTIVE
    }`
  }
  return `shrink-0 rounded px-2 py-1 text-sm transition ${
    active ? NAV_ITEM_ACTIVE : NAV_ITEM_INACTIVE
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
    <div className={`${NAV_CHROME_FIXED_ROOT} overflow-visible`}>
      <div className={NAV_CHROME_BAR_SUBTLE_BORDER}>
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
                className={`hidden px-3 sm:px-4 md:inline-flex ${NAV_CTA_PRIMARY}`}
              >
                Return to App
              </button>
            ) : (
              <div className="hidden items-center gap-2 sm:gap-3 md:flex">
                <IntentPrefetchLink
                  href="/login"
                  className="rounded border border-chrome-border px-3 py-1.5 text-sm font-medium text-chrome-foreground transition hover:bg-surface-elevated sm:px-4"
                >
                  Login
                </IntentPrefetchLink>
                <IntentPrefetchLink
                  href="/login?tab=signup"
                  className={`rounded px-3 sm:px-4 ${NAV_CTA_PRIMARY}`}
                >
                  Sign Up
                </IntentPrefetchLink>
              </div>
            )}

            <div className="flex items-center gap-2 md:hidden">
              {!showReturnToApp ? (
                <IntentPrefetchLink
                  href="/login"
                  className="rounded border border-chrome-border px-3 py-1.5 text-sm font-medium text-chrome-foreground transition hover:bg-surface-elevated"
                >
                  Login
                </IntentPrefetchLink>
              ) : null}
              <button
                type="button"
                className="px-1 py-1 text-2xl leading-none text-chrome-foreground"
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
        <div className={NAV_PUBLIC_MOBILE_MENU}>
          <nav
            className="flex w-full flex-col gap-2 px-4 pb-[calc(0.75rem+var(--safe-area-bottom))] pt-1.5 text-sm text-chrome-foreground md:px-6"
            aria-label="Marketing menu"
          >
            {showReturnToApp ? (
              <>
                <button
                  type="button"
                  onClick={handleReturnToApp}
                  className={`rounded-lg px-3 py-2 text-left font-semibold transition ${NAV_LINK_SECONDARY_HOVER_ACCENT}`}
                >
                  Return to App
                </button>
                <div className={`my-1 ${NAV_DIVIDER}`} aria-hidden />
              </>
            ) : (
              <>
                <IntentPrefetchLink
                  href="/login?tab=signup"
                  className={`rounded-lg px-3 py-2 font-semibold transition ${NAV_LINK_SECONDARY_HOVER_ACCENT}`}
                  onClick={() => setMenuOpen(false)}
                >
                  Sign Up
                </IntentPrefetchLink>
                <IntentPrefetchLink
                  href="/login"
                  className={`rounded-lg px-3 py-2 font-semibold transition ${NAV_LINK_SECONDARY_HOVER_ACCENT}`}
                  onClick={() => setMenuOpen(false)}
                >
                  Login
                </IntentPrefetchLink>
                <div className={`my-1 ${NAV_DIVIDER}`} aria-hidden />
              </>
            )}
            {renderNavLinks(true)}
          </nav>
        </div>
      ) : null}
    </div>
  )
}
