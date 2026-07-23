"use client"

import IntentPrefetchLink from "@/lib/IntentPrefetchLink"
import {
  CirclePlus,
  House,
  LayoutDashboard,
  Menu,
  User,
} from "lucide-react"
import { usePathname } from "next/navigation"
import { openNativeIosAppMenu } from "@/lib/nativeIosAppMenu"
import { profilePath } from "@/lib/profileRoutes"
import { useUserProfile } from "@/lib/useUserProfile"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import { hapticLight } from "@/lib/nativeHaptics"

type TabDef =
  | {
      id: "feed" | "dashboard" | "add" | "profile"
      label: string
      href: string
      Icon: typeof House
      isActive: (pathname: string, profileHref: string | null) => boolean
    }
  | {
      id: "more"
      label: string
      Icon: typeof Menu
    }

/**
 * Fixed iOS Capacitor tab bar. Web / Android / Safari never mount this.
 * "More" opens the existing Navbar hamburger menu (no new page).
 */
export default function NativeIosBottomNav() {
  const enabled = useIsNativeIos()
  const pathname = usePathname() || "/"
  const { user, profile } = useUserProfile()

  const profileHref =
    profile != null
      ? profilePath(profile)
      : user?.id
        ? profilePath({ id: user.id })
        : "/profile"

  if (!enabled) return null
  // Same mount gate as the app Navbar — no tab bar on marketing/auth chrome.
  if (!user && !pathname.startsWith("/demo")) return null

  const tabs: TabDef[] = [
    {
      id: "feed",
      label: "Feed",
      href: "/feed",
      Icon: House,
      isActive: (p) => p === "/feed" || p.startsWith("/feed/"),
    },
    {
      id: "dashboard",
      label: "Dashboard",
      href: "/dashboard",
      Icon: LayoutDashboard,
      isActive: (p) => p === "/dashboard" || p.startsWith("/dashboard/"),
    },
    {
      id: "add",
      label: "Add",
      href: "/app",
      Icon: CirclePlus,
      isActive: (p) =>
        p === "/app" || p.startsWith("/app/") || p === "/input-trade",
    },
    {
      id: "profile",
      label: "Profile",
      href: profileHref,
      Icon: User,
      isActive: (p, href) => {
        if (!href) return false
        if (p === href) return true
        // Username or id segment for own profile.
        return p.startsWith(`${href}/`)
      },
    },
    {
      id: "more",
      label: "More",
      Icon: Menu,
    },
  ]

  return (
    <nav
      data-native-ios-bottom-nav
      aria-label="Primary"
      className="fixed inset-x-0 bottom-0 z-[9998] border-t border-white/10 bg-[#0b1f3a] pb-[var(--safe-area-bottom)] pt-1 text-gray-300 md:hidden"
    >
      <ul className="grid h-[var(--app-tab-bar-height)] grid-cols-5 items-stretch">
        {tabs.map((tab) => {
          if (tab.id === "more") {
            return (
              <li key={tab.id} className="min-w-0">
                <button
                  type="button"
                  onClick={() => openNativeIosAppMenu()}
                  className="flex h-full w-full flex-col items-center justify-center gap-0.5 text-[10px] font-medium text-gray-300 active:text-white"
                  aria-label="Open menu"
                >
                  <Menu className="h-6 w-6 shrink-0" strokeWidth={1.75} aria-hidden />
                  <span className="leading-none">{tab.label}</span>
                </button>
              </li>
            )
          }

          const active = tab.isActive(pathname, profileHref)
          return (
            <li key={tab.id} className="min-w-0">
              <IntentPrefetchLink
                href={tab.href}
                onClick={() => hapticLight(`tab-${tab.id}`)}
                className={`flex h-full w-full flex-col items-center justify-center gap-0.5 text-[10px] font-medium transition-colors ${
                  active ? "text-blue-300" : "text-gray-300 active:text-white"
                }`}
                aria-current={active ? "page" : undefined}
              >
                <tab.Icon
                  className="h-6 w-6 shrink-0"
                  strokeWidth={active ? 2.25 : 1.75}
                  aria-hidden
                />
                <span className="leading-none">{tab.label}</span>
              </IntentPrefetchLink>
            </li>
          )
        })}
      </ul>
    </nav>
  )
}
