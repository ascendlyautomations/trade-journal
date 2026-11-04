"use client"

import "./publicNavbarTheme.css"
import IntentPrefetchLink from "@/lib/IntentPrefetchLink"
import { usePathname, useRouter } from "next/navigation"
import {
  useCallback,
  useEffect,
  useId,
  useRef,
  useState,
  type MouseEvent,
} from "react"
import { ChevronDown, ChevronRight } from "lucide-react"
import { useUserProfile } from "@/lib/useUserProfile"
import { isAuthRoute } from "@/lib/authRoutes"
import {
  shouldShowCustomerHomeChrome,
  shouldShowMarketingNavbar,
} from "@/lib/marketingAccess"
import { NAVBAR_BRAND_LINK_CLASS_NOWRAP } from "@/lib/navbarBrand"
import { navigateToComingSoonSection } from "@/app/components/landing/LandingComingSoonSection"
import LandingAppStoreButton from "@/app/components/landing/v2/LandingAppStoreButton"
import {
  NAV_CHROME_BAR_SUBTLE_BORDER,
  NAV_CHROME_FIXED_ROOT,
  NAV_CTA_PRIMARY,
  NAV_DIVIDER,
  NAV_DROPDOWN_PANEL,
  NAV_ITEM_ACTIVE,
  NAV_ITEM_INACTIVE,
  NAV_ITEM_INACTIVE_HOVER_SURFACE,
  NAV_LINK_SECONDARY_HOVER_ACCENT,
  NAV_PUBLIC_MOBILE_MENU,
} from "@/lib/navChromeStyles"

/** Matches documents on `/legal` — nav labels only. */
const LEGAL_NAV_LINKS = [
  { href: "/privacy", label: "Privacy Policy" },
  { href: "/terms", label: "Terms of Service" },
  { href: "/affiliate-terms", label: "Affiliate Terms" },
  { href: "/refund-policy", label: "Refund Policy" },
  { href: "/cookie-policy", label: "Cookie Policy" },
  { href: "/acceptable-use", label: "Acceptable Use Policy" },
  { href: "/copyright", label: "Copyright & DMCA Policy" },
  { href: "/community-guidelines", label: "Community Guidelines" },
] as const

const SIMPLE_NAV_LINKS = [
  { href: "/#features", label: "Features" },
  { href: "/demo", label: "Demo" },
  { href: "/pricing", label: "Pricing" },
  { href: "/affiliate", label: "Affiliate" },
  { href: "/faq", label: "FAQ" },
] as const

const COMING_SOON_NAV_HREF = "/#coming-soon"

function isNavLinkActive(pathname: string, href: string): boolean {
  if (href === "/affiliate") {
    return pathname === "/affiliate"
  }
  if (href.startsWith("/#")) {
    return false
  }
  return pathname === href
}

function isAboutSectionActive(pathname: string): boolean {
  if (pathname === "/about" || pathname === "/contact" || pathname === "/legal") {
    return true
  }
  return LEGAL_NAV_LINKS.some((link) => pathname === link.href)
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

function dropdownRowClass(active: boolean): string {
  return `block w-full rounded-md px-3 py-2 text-left text-sm transition ${
    active ? NAV_ITEM_ACTIVE : NAV_ITEM_INACTIVE_HOVER_SURFACE
  }`
}

/** Marketing navbar — logged-out visitors and completed members on public pages. */
export default function PublicNavbar() {
  const { user, profile, loading } = useUserProfile()
  const pathname = usePathname()
  const router = useRouter()
  const [menuOpen, setMenuOpen] = useState(false)
  const [comingSoonActive, setComingSoonActive] = useState(false)
  const [aboutOpen, setAboutOpen] = useState(false)
  const [mobileAboutOpen, setMobileAboutOpen] = useState(false)
  const [legalSubOpen, setLegalSubOpen] = useState(false)
  const aboutMenuRef = useRef<HTMLDivElement>(null)
  const aboutMenuId = useId()

  const showReturnToApp = shouldShowCustomerHomeChrome(user, profile, loading)

  const closeAboutMenu = useCallback(() => {
    setAboutOpen(false)
    setLegalSubOpen(false)
  }, [])

  useEffect(() => {
    setMenuOpen(false)
    closeAboutMenu()
    setMobileAboutOpen(false)
  }, [pathname, closeAboutMenu])

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

  useEffect(() => {
    if (!aboutOpen) return
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") closeAboutMenu()
    }
    function onPointerDown(e: Event) {
      const root = aboutMenuRef.current
      if (!root?.contains(e.target as Node)) closeAboutMenu()
    }
    window.addEventListener("keydown", onKeyDown)
    document.addEventListener("mousedown", onPointerDown)
    document.addEventListener("touchstart", onPointerDown)
    return () => {
      window.removeEventListener("keydown", onKeyDown)
      document.removeEventListener("mousedown", onPointerDown)
      document.removeEventListener("touchstart", onPointerDown)
    }
  }, [aboutOpen, closeAboutMenu])

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

  function renderSimpleLinks(mobile: boolean) {
    const classFor = mobile ? mobileNavLinkClass : navLinkClass
    return SIMPLE_NAV_LINKS.map((link) => (
      <IntentPrefetchLink
        key={link.href}
        href={link.href}
        className={classFor(pathname, link.href)}
        onClick={mobile ? () => setMenuOpen(false) : undefined}
      >
        {link.label}
      </IntentPrefetchLink>
    ))
  }

  function renderRoadmapLink(mobile: boolean) {
    return (
      <a
        key={COMING_SOON_NAV_HREF}
        href={COMING_SOON_NAV_HREF}
        className={comingSoonNavClass(comingSoonActive, mobile)}
        onClick={handleComingSoonClick}
      >
        Roadmap
      </a>
    )
  }

  function renderDesktopAboutMenu() {
    const triggerActive = isAboutSectionActive(pathname)
    return (
      <div ref={aboutMenuRef} className="relative shrink-0">
        <button
          type="button"
          id={`${aboutMenuId}-trigger`}
          aria-expanded={aboutOpen}
          aria-haspopup="menu"
          aria-controls={`${aboutMenuId}-menu`}
          className={`inline-flex items-center gap-0.5 rounded px-2 py-1 text-sm transition ${
            triggerActive || aboutOpen ? NAV_ITEM_ACTIVE : NAV_ITEM_INACTIVE
          }`}
          onClick={() => {
            setAboutOpen((open) => !open)
            if (aboutOpen) setLegalSubOpen(false)
          }}
        >
          About
          <ChevronDown
            className={`h-3.5 w-3.5 opacity-80 transition-transform duration-200 ${
              aboutOpen ? "rotate-180" : ""
            }`}
            aria-hidden
          />
        </button>
        {aboutOpen ? (
          <div
            id={`${aboutMenuId}-menu`}
            role="menu"
            aria-labelledby={`${aboutMenuId}-trigger`}
            className={`tt-public-nav-dropdown ${NAV_DROPDOWN_PANEL} left-0 w-64 overflow-hidden rounded-lg py-1`}
          >
            <IntentPrefetchLink
              href="/about"
              role="menuitem"
              className={dropdownRowClass(pathname === "/about")}
              onClick={closeAboutMenu}
            >
              About Us
            </IntentPrefetchLink>
            <IntentPrefetchLink
              href="/contact"
              role="menuitem"
              className={dropdownRowClass(pathname === "/contact")}
              onClick={closeAboutMenu}
            >
              Contact
            </IntentPrefetchLink>
            <div className="my-1 border-t border-border" role="none" />
            <button
              type="button"
              role="menuitem"
              aria-expanded={legalSubOpen}
              className={`flex w-full items-center justify-between gap-2 rounded-md px-3 py-2 text-left text-sm transition ${NAV_ITEM_INACTIVE_HOVER_SURFACE}`}
              onClick={() => setLegalSubOpen((open) => !open)}
            >
              <span>Legal</span>
              <ChevronRight
                className={`h-3.5 w-3.5 shrink-0 opacity-70 transition-transform duration-200 ${
                  legalSubOpen ? "rotate-90" : ""
                }`}
                aria-hidden
              />
            </button>
            {legalSubOpen ? (
              <div
                className="border-t border-border bg-surface-elevated/40 px-1 pb-1 pt-0.5"
                role="group"
                aria-label="Legal documents"
              >
                {LEGAL_NAV_LINKS.map((link) => (
                  <IntentPrefetchLink
                    key={link.href}
                    href={link.href}
                    role="menuitem"
                    className={`${dropdownRowClass(pathname === link.href)} pl-4 text-xs`}
                    onClick={closeAboutMenu}
                  >
                    {link.label}
                  </IntentPrefetchLink>
                ))}
              </div>
            ) : null}
          </div>
        ) : null}
      </div>
    )
  }

  function renderMobileAboutSection() {
    const triggerActive = isAboutSectionActive(pathname)
    return (
      <div className="flex flex-col gap-0.5">
        <button
          type="button"
          aria-expanded={mobileAboutOpen}
          className={`flex w-full items-center justify-between rounded-lg px-3 py-2 text-left transition ${
            triggerActive || mobileAboutOpen ? NAV_ITEM_ACTIVE : NAV_ITEM_INACTIVE
          }`}
          onClick={() => setMobileAboutOpen((open) => !open)}
        >
          <span>About</span>
          <ChevronDown
            className={`h-4 w-4 opacity-80 transition-transform duration-200 ${
              mobileAboutOpen ? "rotate-180" : ""
            }`}
            aria-hidden
          />
        </button>
        {mobileAboutOpen ? (
          <div className="ml-2 flex flex-col gap-0.5 border-l border-border pl-2">
            <IntentPrefetchLink
              href="/about"
              className={mobileNavLinkClass(pathname, "/about")}
              onClick={() => setMenuOpen(false)}
            >
              About Us
            </IntentPrefetchLink>
            <IntentPrefetchLink
              href="/contact"
              className={mobileNavLinkClass(pathname, "/contact")}
              onClick={() => setMenuOpen(false)}
            >
              Contact
            </IntentPrefetchLink>
            <button
              type="button"
              aria-expanded={legalSubOpen}
              className={`flex w-full items-center justify-between rounded-lg px-3 py-2 text-left transition ${NAV_ITEM_INACTIVE}`}
              onClick={() => setLegalSubOpen((open) => !open)}
            >
              <span>Legal</span>
              <ChevronRight
                className={`h-4 w-4 opacity-80 transition-transform duration-200 ${
                  legalSubOpen ? "rotate-90" : ""
                }`}
                aria-hidden
              />
            </button>
            {legalSubOpen ? (
              <div className="ml-2 flex flex-col gap-0.5 border-l border-border pl-2">
                {LEGAL_NAV_LINKS.map((link) => (
                  <IntentPrefetchLink
                    key={link.href}
                    href={link.href}
                    className={mobileNavLinkClass(pathname, link.href)}
                    onClick={() => setMenuOpen(false)}
                  >
                    {link.label}
                  </IntentPrefetchLink>
                ))}
              </div>
            ) : null}
          </div>
        ) : null}
      </div>
    )
  }

  function renderDesktopNav() {
    return (
      <>
        {renderSimpleLinks(false).slice(0, 3)}
        {renderRoadmapLink(false)}
        {renderSimpleLinks(false).slice(3)}
        {renderDesktopAboutMenu()}
      </>
    )
  }

  function renderMobileNav() {
    return (
      <>
        {renderSimpleLinks(true).slice(0, 3)}
        {renderRoadmapLink(true)}
        {renderSimpleLinks(true).slice(3)}
        {renderMobileAboutSection()}
      </>
    )
  }

  return (
    <div className={`${NAV_CHROME_FIXED_ROOT} tt-public-navbar overflow-visible`}>
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
              {renderDesktopNav()}
            </nav>
          </div>

          <div className="flex shrink-0 items-center gap-2 whitespace-nowrap sm:gap-3">
            {showReturnToApp ? (
              <button
                type="button"
                onClick={handleReturnToApp}
                className={`hidden items-center whitespace-nowrap px-3 py-1.5 sm:px-4 md:inline-flex ${NAV_CTA_PRIMARY}`}
              >
                Return to App
              </button>
            ) : (
              <div className="tt-nav-cta-row hidden items-center gap-2 sm:gap-3 md:flex">
                <LandingAppStoreButton surface="nav" className="tt-nav-cta-match" />
                <IntentPrefetchLink
                  href="/login"
                  className="tt-nav-cta-match inline-flex items-center justify-center rounded border border-chrome-border px-3 text-sm font-medium text-chrome-foreground transition hover:bg-surface-elevated sm:px-4"
                >
                  Login
                </IntentPrefetchLink>
                <IntentPrefetchLink
                  href="/login?tab=signup"
                  className={`tt-nav-cta-match inline-flex items-center justify-center whitespace-nowrap px-3 sm:px-4 ${NAV_CTA_PRIMARY}`}
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
                <div className="px-3 py-1">
                  <LandingAppStoreButton surface="nav" />
                </div>
                <div className={`my-1 ${NAV_DIVIDER}`} aria-hidden />
              </>
            )}
            {renderMobileNav()}
          </nav>
        </div>
      ) : null}
    </div>
  )
}
