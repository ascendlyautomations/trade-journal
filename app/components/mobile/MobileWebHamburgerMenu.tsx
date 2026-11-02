"use client"

import IntentPrefetchLink from "@/lib/IntentPrefetchLink"
import { CREATE_ROUTE } from "@/lib/createRoutes"
import type { MobileWebHamburgerSection } from "@/lib/mobileWebHamburger"
import {
  NAV_CTA_PRIMARY,
  NAV_ITEM_ACTIVE,
  NAV_ITEM_INACTIVE,
  NAV_ITEM_INACTIVE_HOVER_SURFACE,
  NAV_UNREAD_BADGE,
} from "@/lib/navChromeStyles"
import {
  ArrowLeftRight,
  BarChart3,
  Bell,
  ChevronDown,
  ChevronUp,
  CircleHelp,
  CirclePlus,
  Home,
  LogOut,
  Settings,
  Shield,
  Users,
  type LucideIcon,
} from "lucide-react"
import type { MouseEvent as ReactMouseEvent, ReactNode } from "react"

const CREATE_ENTRIES = [
  { href: CREATE_ROUTE.addTrade, label: "Add Trade" },
  { href: CREATE_ROUTE.post, label: "Post" },
  { href: CREATE_ROUTE.clip, label: "Clip" },
  { href: CREATE_ROUTE.achievement, label: "Achievement" },
  { href: CREATE_ROUTE.withdrawal, label: "Withdrawal" },
  { href: CREATE_ROUTE.story, label: "Story" },
] as const

const ROW =
  "tt-mobile-web-press flex min-h-11 w-full items-center gap-3 rounded-lg px-3 py-2 text-left transition"
const SECTION_PANEL =
  "overflow-hidden transition-[max-height] duration-200 ease-out"
const ICON = "h-5 w-5 shrink-0"

function rowClass(active: boolean, muted = false) {
  if (active) return `${ROW} ${NAV_ITEM_ACTIVE}`
  if (muted) return `${ROW} ${NAV_ITEM_INACTIVE}`
  return `${ROW} ${NAV_ITEM_INACTIVE_HOVER_SURFACE}`
}

function AccordionSection({
  id,
  label,
  icon: Icon,
  open,
  childActive,
  onToggle,
  children,
}: {
  id: MobileWebHamburgerSection
  label: string
  icon: LucideIcon
  open: boolean
  childActive: boolean
  onToggle: (id: MobileWebHamburgerSection) => void
  children: ReactNode
}) {
  return (
    <div>
      <button
        type="button"
        aria-expanded={open}
        aria-controls={`tt-mobile-web-hamburger-${id}`}
        onClick={() => onToggle(id)}
        className={`${ROW} justify-between ${
          childActive && !open
            ? NAV_ITEM_ACTIVE
            : NAV_ITEM_INACTIVE_HOVER_SURFACE
        }`}
      >
        <span className="flex min-w-0 items-center gap-3">
          <Icon className={ICON} aria-hidden />
          <span className="font-medium">{label}</span>
        </span>
        {open ? (
          <ChevronUp className="h-4 w-4 shrink-0" aria-hidden />
        ) : (
          <ChevronDown className="h-4 w-4 shrink-0" aria-hidden />
        )}
      </button>
      <div
        id={`tt-mobile-web-hamburger-${id}`}
        role="region"
        aria-label={label}
        aria-hidden={!open}
        inert={open ? undefined : true}
        className={SECTION_PANEL}
        style={{ maxHeight: open ? "48rem" : 0 }}
      >
        <div className="flex flex-col gap-0.5 pb-1 pl-3">{children}</div>
      </div>
    </div>
  )
}

export type MobileWebHamburgerCommunityLink = {
  label: string
  href: string
}

type MobileWebHamburgerMenuProps = {
  header?: ReactNode
  pathname: string
  openSection: string | null
  onToggleSection: (section: string) => void
  onNavigate: () => void
  unreadCount: number
  badgeText: (count: number) => string
  isActive: (path: string) => boolean
  isGroupActive: (paths: string[]) => boolean
  analyticsItems: ReactNode
  communityLinks: MobileWebHamburgerCommunityLink[]
  affiliateMenuItem: { label: string; href: string }
  isAdmin: boolean
  onOpenNotifications: () => void
  onOpenReview: () => void
  onOpenBugReport: () => void
  onSignOut: () => void
}

/**
 * Phone-web hamburger (≤767px). Mirrors desktop Navbar order with accordions.
 * Capacitor and desktop chrome never mount this.
 */
export default function MobileWebHamburgerMenu({
  header,
  pathname,
  openSection,
  onToggleSection,
  onNavigate,
  unreadCount,
  badgeText,
  isActive,
  isGroupActive,
  analyticsItems,
  communityLinks,
  affiliateMenuItem,
  isAdmin,
  onOpenNotifications,
  onOpenReview,
  onOpenBugReport,
  onSignOut,
}: MobileWebHamburgerMenuProps) {
  const createActive = openSection === "create"
  const analyticsActive = openSection === "analytics"
  const communityActive = openSection === "community"
  const accountActive = openSection === "account"
  const supportActive = openSection === "support"

  const createChildActive = CREATE_ENTRIES.some((entry) => isActive(entry.href))
  const analyticsChildActive = isGroupActive([
    "/analytics",
    "/backtest",
    "/calendar",
    "/streaks",
    "/achievements",
    "/analyst",
  ])
  const communityChildActive = isGroupActive([
    "/community",
    "/trade-rooms",
    "/leaderboard",
    "/explore",
    "/room/",
  ])
  const accountChildActive = isGroupActive([
    "/settings",
    "/notifications",
    "/referrals",
    "/affiliate",
    "/payouts",
  ])
  const supportChildActive = isGroupActive([
    "/help",
    "/privacy",
    "/terms",
    "/feature-requests",
  ])

  return (
    <nav aria-label="App" className="flex w-full flex-col gap-0.5">
      {header}

      <AccordionSection
        id="create"
        label="Create"
        icon={CirclePlus}
        open={createActive}
        childActive={createChildActive}
        onToggle={onToggleSection}
      >
        {CREATE_ENTRIES.map((entry) => (
          <IntentPrefetchLink
            key={entry.href}
            href={entry.href}
            className={rowClass(isActive(entry.href))}
            onClick={onNavigate}
          >
            {entry.label}
          </IntentPrefetchLink>
        ))}
      </AccordionSection>

      <IntentPrefetchLink
        href="/trades"
        data-tt-tour-target="dashboardTrades"
        className={rowClass(isActive("/trades"))}
        onClick={onNavigate}
      >
        <ArrowLeftRight className={ICON} aria-hidden />
        Trades
      </IntentPrefetchLink>

      <div className="mt-1 border-t border-border pt-1" role="presentation" />

      <AccordionSection
        id="analytics"
        label="Analytics"
        icon={BarChart3}
        open={analyticsActive}
        childActive={analyticsChildActive}
        onToggle={onToggleSection}
      >
        {analyticsItems}
      </AccordionSection>

      <AccordionSection
        id="community"
        label="Community"
        icon={Users}
        open={communityActive}
        childActive={communityChildActive}
        onToggle={onToggleSection}
      >
        {communityLinks.map((item) => (
          <IntentPrefetchLink
            key={item.href}
            href={item.href}
            data-tt-tour-target={
              item.href === "/community"
                ? "feedTradeRooms"
                : item.href === "/explore"
                  ? "feedExplore"
                  : undefined
            }
            className={rowClass(
              item.href === "/community"
                ? isActive(item.href) || pathname.startsWith("/room/")
                : isActive(item.href)
            )}
            onClick={onNavigate}
          >
            {item.label}
          </IntentPrefetchLink>
        ))}
      </AccordionSection>

      <div className="mt-1 border-t border-border pt-1" role="presentation" />

      <IntentPrefetchLink
        href="/"
        className={rowClass(isActive("/"))}
        onClick={onNavigate}
      >
        <Home className={ICON} aria-hidden />
        TradeTraxs Homepage
      </IntentPrefetchLink>

      <AccordionSection
        id="account"
        label="Account"
        icon={Settings}
        open={accountActive}
        childActive={accountChildActive}
        onToggle={onToggleSection}
      >
        <IntentPrefetchLink
          href="/settings#account"
          className={rowClass(isGroupActive(["/settings"]))}
          onClick={onNavigate}
        >
          Settings
        </IntentPrefetchLink>
        <IntentPrefetchLink
          href={affiliateMenuItem.href}
          className={rowClass(
            isGroupActive([
              "/affiliate",
              "/affiliate/dashboard",
              "/affiliate/payout-setup",
              "/payouts",
            ])
          )}
          onClick={onNavigate}
        >
          {affiliateMenuItem.label}
        </IntentPrefetchLink>
        <IntentPrefetchLink
          href="/settings#subscription"
          className={rowClass(false)}
          onClick={onNavigate}
        >
          Billing / Subscription
        </IntentPrefetchLink>
        <button
          type="button"
          className={`${rowClass(isActive("/notifications"))} justify-between`}
          onClick={onOpenNotifications}
        >
          <span className="flex min-w-0 items-center gap-3">
            <Bell className={ICON} aria-hidden />
            Notifications
          </span>
          {unreadCount > 0 ? (
            <span className={`px-2 py-0.5 text-xs tabular-nums ${NAV_UNREAD_BADGE}`}>
              {badgeText(unreadCount)}
            </span>
          ) : null}
        </button>
        <IntentPrefetchLink
          href="/referrals"
          className={rowClass(isActive("/referrals"))}
          onClick={onNavigate}
        >
          Referrals
        </IntentPrefetchLink>
      </AccordionSection>

      <AccordionSection
        id="support"
        label="Support"
        icon={CircleHelp}
        open={supportActive}
        childActive={supportChildActive}
        onToggle={onToggleSection}
      >
        <IntentPrefetchLink
          href="/help"
          className={rowClass(isActive("/help"))}
          onClick={onNavigate}
        >
          Help Center
        </IntentPrefetchLink>
        <button
          type="button"
          className={rowClass(false)}
          onClick={onOpenReview}
        >
          Leave a Review
        </button>
        <button
          type="button"
          className={rowClass(false)}
          onClick={onOpenBugReport}
        >
          Report Bug
        </button>
        <IntentPrefetchLink
          href="/feature-requests"
          className={rowClass(isActive("/feature-requests"))}
          onClick={onNavigate}
        >
          Feature Requests
        </IntentPrefetchLink>
        <IntentPrefetchLink
          href="/privacy"
          className={rowClass(isActive("/privacy"))}
          onClick={onNavigate}
        >
          Privacy Policy
        </IntentPrefetchLink>
        <IntentPrefetchLink
          href="/terms"
          className={rowClass(isActive("/terms"))}
          onClick={onNavigate}
        >
          Terms of Service
        </IntentPrefetchLink>
      </AccordionSection>

      {isAdmin ? (
        <IntentPrefetchLink
          href="/admin"
          className={rowClass(isGroupActive(["/admin"]))}
          onClick={onNavigate}
        >
          <Shield className={ICON} aria-hidden />
          Admin
        </IntentPrefetchLink>
      ) : null}

      <div className="mt-1 border-t border-border pt-1.5">
        <button
          type="button"
          className={`${ROW} text-sm text-red-400 hover:text-red-300`}
          onClick={onSignOut}
        >
          <LogOut className={ICON} aria-hidden />
          Sign Out
        </button>
      </div>
    </nav>
  )
}

export function MobileWebHamburgerHeader({
  showReturnToApp,
  onReturnToApp,
  gettingStarted,
}: {
  showReturnToApp: boolean
  onReturnToApp: (e: ReactMouseEvent<HTMLButtonElement>) => void
  gettingStarted?: ReactNode
}) {
  return (
    <>
      {showReturnToApp ? (
        <button
          type="button"
          onClick={onReturnToApp}
          className={`mb-1 w-fit self-start whitespace-nowrap rounded-lg px-3 py-2 font-medium ${NAV_CTA_PRIMARY}`}
        >
          Return to App
        </button>
      ) : null}
      {gettingStarted}
    </>
  )
}
