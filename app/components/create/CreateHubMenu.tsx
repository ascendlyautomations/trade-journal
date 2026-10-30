"use client"

import { useCallback, useEffect, useRef, useState, type ReactNode } from "react"
import { createPortal } from "react-dom"
import { usePathname, useRouter } from "next/navigation"
import IntentPrefetchLink from "@/lib/IntentPrefetchLink"
import { CREATE_ROUTE, isCreateHubPath } from "@/lib/createRoutes"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { isAppAddTradePath } from "@/lib/addTradePath"
import {
  Camera,
  CirclePlus,
  MessageSquareText,
  PlaySquare,
  Trophy,
  ArrowDownCircle,
} from "lucide-react"
import {
  NAV_DROPDOWN_PANEL,
  NAV_ITEM_ACTIVE,
  NAV_ITEM_INACTIVE,
  NAV_ITEM_INACTIVE_HOVER_SURFACE,
  NAV_MENU_ROW,
  NAV_SECTION_LABEL,
} from "@/lib/navChromeStyles"
import { UI_MODAL_BACKDROP } from "@/lib/uiPrimitiveStyles"

type CreateMenuEntry = {
  id: string
  label: string
  subtitle?: string
  href?: string
  onSelect?: () => void
  icon: ReactNode
}

type CreateHubMenuProps = {
  /** Navbar text trigger vs profile primary button styling vs tab-bar controller */
  variant: "navbar" | "profile-button" | "controller"
  navTriggerClass?: (active: boolean) => string
  onNavigate?: () => void
  className?: string
  open?: boolean
  onOpenChange?: (open: boolean) => void
}

function TradeIcon() {
  return <span aria-hidden>➕</span>
}
function PostIcon() {
  return <span aria-hidden>📝</span>
}
function ClipIcon() {
  return <span aria-hidden>🎥</span>
}
function AchievementIcon() {
  return <span aria-hidden>🏆</span>
}
function StoryIcon() {
  return <span aria-hidden>📖</span>
}
function WithdrawalIcon() {
  return <span aria-hidden>💸</span>
}

function TradeLucideIcon() {
  return <CirclePlus className="h-4 w-4" aria-hidden />
}
function PostLucideIcon() {
  return <MessageSquareText className="h-4 w-4" aria-hidden />
}
function ClipLucideIcon() {
  return <PlaySquare className="h-4 w-4" aria-hidden />
}
function AchievementLucideIcon() {
  return <Trophy className="h-4 w-4" aria-hidden />
}
function StoryLucideIcon() {
  return <Camera className="h-4 w-4" aria-hidden />
}
function WithdrawalLucideIcon() {
  return <ArrowDownCircle className="h-4 w-4" aria-hidden />
}

function MenuOptionsList({
  items,
  onItemAction,
  dense = true,
}: {
  items: CreateMenuEntry[]
  onItemAction: (item: CreateMenuEntry) => void
  /** Desktop dropdown keeps compact rows. Phone sheet uses 44px targets. */
  dense?: boolean
}) {
  return (
    <ul className="p-1.5" role="menu">
      {items.map((item) => (
        <li key={item.id} role="none">
          <button
            type="button"
            role="menuitem"
            onClick={() => onItemAction(item)}
            className={`flex w-full items-center gap-3 rounded-lg px-3 text-left text-sm ${
              dense ? "py-2" : "min-h-11 py-2.5"
            } ${NAV_ITEM_INACTIVE_HOVER_SURFACE}`}
          >
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border border-border bg-surface-elevated text-base">
              {item.icon}
            </span>
            <span className="min-w-0 flex-1">
              <span className="block font-medium text-chrome-foreground">{item.label}</span>
              {item.subtitle ? (
                <span className="block text-xs text-muted-foreground">{item.subtitle}</span>
              ) : null}
            </span>
          </button>
        </li>
      ))}
    </ul>
  )
}

export default function CreateHubMenu({
  variant,
  navTriggerClass,
  onNavigate,
  className,
  open: openProp,
  onOpenChange,
}: CreateHubMenuProps) {
  const router = useRouter()
  const pathname = usePathname() || "/"
  const [uncontrolledOpen, setUncontrolledOpen] = useState(false)
  const [isMobile, setIsMobile] = useState(false)
  const [mounted, setMounted] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)
  const isController = variant === "controller"
  const open = isController ? Boolean(openProp) : uncontrolledOpen
  const setOpen = useCallback(
    (next: boolean | ((prev: boolean) => boolean)) => {
      const resolved = typeof next === "function" ? next(open) : next
      if (isController) {
        onOpenChange?.(resolved)
        return
      }
      setUncontrolledOpen(resolved)
    },
    [isController, onOpenChange, open]
  )

  const close = useCallback(() => setOpen(false), [setOpen])
  const useNativeIcons = isMobile || isController

  const menuItems: CreateMenuEntry[] = [
    {
      id: "add-trade",
      label: "Add Trade",
      subtitle: "Log a completed trade",
      href: CREATE_ROUTE.addTrade,
      icon: useNativeIcons ? <TradeLucideIcon /> : <TradeIcon />,
    },
    {
      id: "post",
      label: "Post",
      subtitle: "Share with the community",
      href: CREATE_ROUTE.post,
      icon: useNativeIcons ? <PostLucideIcon /> : <PostIcon />,
    },
    {
      id: "clip",
      label: "Clip",
      subtitle: "Upload a short video",
      href: CREATE_ROUTE.clip,
      icon: useNativeIcons ? <ClipLucideIcon /> : <ClipIcon />,
    },
    {
      id: "achievement",
      label: "Achievement",
      subtitle: "Share a milestone",
      href: CREATE_ROUTE.achievement,
      icon: useNativeIcons ? <AchievementLucideIcon /> : <AchievementIcon />,
    },
    {
      id: "withdrawal",
      label: "Withdrawal",
      subtitle: "Record a Live or prop-firm payout",
      href: CREATE_ROUTE.withdrawal,
      icon: useNativeIcons ? <WithdrawalLucideIcon /> : <WithdrawalIcon />,
    },
    {
      id: "story",
      label: "Story",
      subtitle: "Photo for 24 hours",
      href: CREATE_ROUTE.story,
      icon: useNativeIcons ? <StoryLucideIcon /> : <StoryIcon />,
    },
  ]

  const menuActive =
    isCreateHubPath(pathname) || isAppAddTradePath(pathname)

  const handleItemAction = useCallback(
    (item: CreateMenuEntry) => {
      close()
      onNavigate?.()
      if (item.onSelect) {
        item.onSelect()
        return
      }
      if (item.href) {
        router.push(item.href)
      }
    },
    [close, onNavigate, router]
  )

  useEffect(() => setMounted(true), [])

  useEffect(() => {
    if (typeof window === "undefined") return
    const mq = window.matchMedia("(max-width: 767px)")
    const sync = () => setIsMobile(mq.matches)
    sync()
    mq.addEventListener("change", sync)
    return () => mq.removeEventListener("change", sync)
  }, [])

  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") close()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, close])

  useModalScrollLock(open && (isMobile || isController))

  useEffect(() => {
    if (!open || isMobile) return
    function onPointerDown(e: MouseEvent | TouchEvent) {
      const root = rootRef.current
      if (!root?.contains(e.target as Node)) close()
    }
    document.addEventListener("mousedown", onPointerDown)
    document.addEventListener("touchstart", onPointerDown)
    return () => {
      document.removeEventListener("mousedown", onPointerDown)
      document.removeEventListener("touchstart", onPointerDown)
    }
  }, [open, isMobile, close])

  const trigger =
    variant === "navbar" ? (
      <button
        type="button"
        onClick={() => setOpen((prev) => !prev)}
        aria-expanded={open}
        aria-haspopup="menu"
        className={
          navTriggerClass?.(menuActive) ??
          `shrink-0 rounded px-2 py-1 transition ${
            menuActive ? NAV_ITEM_ACTIVE : NAV_ITEM_INACTIVE
          }`
        }
      >
        + Create
      </button>
    ) : null

  const sheet =
    open && mounted && (isMobile || isController)
      ? createPortal(
          <div
            className="fixed inset-0 z-[10050] md:hidden"
            role="presentation"
            onClick={close}
          >
            <div className={UI_MODAL_BACKDROP} aria-hidden />
            <div
              role="dialog"
              aria-modal="true"
              aria-label="Create"
              className="absolute inset-x-0 bottom-0 rounded-t-2xl border border-border bg-card text-card-foreground shadow-modal ui-theme-backdrop"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex justify-center pt-3 pb-1">
                <div className="h-1 w-10 rounded-full bg-border" aria-hidden />
              </div>
              <div className="border-b border-divider px-4 pb-3">
                <h2 className="text-base font-semibold text-foreground">Create</h2>
                <p className="mt-0.5 text-xs text-muted-foreground">
                  Trade journal & community content
                </p>
              </div>
              <MenuOptionsList
                items={menuItems}
                onItemAction={handleItemAction}
                dense={false}
              />
              <div className="border-t border-divider p-3">
                <button
                  type="button"
                  onClick={close}
                  className={`${NAV_MENU_ROW} min-h-11`}
                >
                  Cancel
                </button>
              </div>
              <div className="h-[max(0.75rem,var(--safe-area-bottom))]" />
            </div>
          </div>,
          document.body
        )
      : null

  if (variant === "profile-button") return null

  if (variant === "controller") {
    return <>{sheet}</>
  }

  return (
    <div ref={rootRef} className={`relative shrink-0 ${className ?? ""}`}>
      {trigger}
      {open && !isMobile ? (
        <div
          role="menu"
          aria-label="Create"
          className={`${NAV_DROPDOWN_PANEL} left-0 w-64 overflow-hidden rounded-xl`}
        >
          <div className="border-b border-border px-3 py-2">
            <p className={NAV_SECTION_LABEL}>Create</p>
          </div>
          <MenuOptionsList items={menuItems} onItemAction={handleItemAction} />
        </div>
      ) : null}
      {sheet}
    </div>
  )
}

/** Mobile drawer section — flat links matching the hub menu. */
export function CreateHubMobileLinks({
  onNavigate,
  linkClass,
}: {
  onNavigate?: () => void
  linkClass: (active: boolean) => string
}) {
  const pathname = usePathname() || "/"
  const entries = [
    { href: CREATE_ROUTE.addTrade, label: "Add Trade" },
    { href: CREATE_ROUTE.post, label: "Post" },
    { href: CREATE_ROUTE.clip, label: "Clip" },
    { href: CREATE_ROUTE.achievement, label: "Achievement" },
    { href: CREATE_ROUTE.withdrawal, label: "Withdrawal" },
    { href: CREATE_ROUTE.story, label: "Story" },
  ]

  return (
    <div className="flex flex-col gap-0.5 border-b border-border pb-2">
      <p className="px-3 py-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
        Create
      </p>
      {entries.map((entry) => (
        <IntentPrefetchLink
          key={entry.href}
          href={entry.href}
          className={linkClass(pathname === entry.href)}
          onClick={onNavigate}
        >
          {entry.label}
        </IntentPrefetchLink>
      ))}
    </div>
  )
}
