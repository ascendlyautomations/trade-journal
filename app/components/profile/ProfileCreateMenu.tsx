"use client"

import { useCallback, useEffect, useRef, useState, type ReactNode } from "react"
import { createPortal } from "react-dom"

type CreateMenuEntry = {
  id: string
  label: string
  icon: ReactNode
  disabled?: boolean
  badge?: string
  onSelect?: () => void
}

type ProfileCreateMenuProps = {
  onCreateStory: () => void
  onCreatePost: () => void
  onCreateReel: () => void
  onCreateQuickTrade: () => void
  /** Header action button vs empty-state text link */
  variant?: "button" | "link"
  className?: string
}

function StoryIcon({ className }: { className?: string }) {
  return (
    <span className={className} aria-hidden>
      📖
    </span>
  )
}

function PostIcon({ className }: { className?: string }) {
  return (
    <span className={className} aria-hidden>
      📝
    </span>
  )
}

function ReelIcon({ className }: { className?: string }) {
  return (
    <span className={className} aria-hidden>
      🎥
    </span>
  )
}

function QuickTradeIcon({ className }: { className?: string }) {
  return (
    <span className={className} aria-hidden>
      ⚡
    </span>
  )
}

function MenuOptionsList({
  items,
  onItemAction,
}: {
  items: CreateMenuEntry[]
  onItemAction: (item: CreateMenuEntry) => void
}) {
  return (
    <ul className="p-1.5" role="menu">
      {items.map((item) => (
        <li key={item.id} role="none">
          <button
            type="button"
            role="menuitem"
            disabled={item.disabled}
            onClick={() => onItemAction(item)}
            className={`flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-left text-sm transition ${
              item.disabled
                ? "cursor-not-allowed text-gray-500"
                : "text-gray-100 hover:bg-emerald-500/15 hover:text-emerald-100"
            }`}
          >
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border border-white/10 bg-white/5 text-base">
              {item.icon}
            </span>
            <span className="min-w-0 flex-1 font-medium">{item.label}</span>
            {item.badge ? (
              <span className="shrink-0 rounded-full border border-white/10 bg-white/5 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-gray-400">
                {item.badge}
              </span>
            ) : null}
          </button>
        </li>
      ))}
    </ul>
  )
}

export default function ProfileCreateMenu({
  onCreateStory,
  onCreatePost,
  onCreateReel,
  onCreateQuickTrade,
  variant = "button",
  className,
}: ProfileCreateMenuProps) {
  const [open, setOpen] = useState(false)
  const [isMobile, setIsMobile] = useState(false)
  const [mounted, setMounted] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)

  const close = useCallback(() => setOpen(false), [])

  // Extend this array to add future content types (Journal, Achievement, Live Stream, etc.)
  const menuItems: CreateMenuEntry[] = [
    {
      id: "story",
      label: "Story",
      icon: <StoryIcon />,
      onSelect: onCreateStory,
    },
    {
      id: "post",
      label: "Post",
      icon: <PostIcon />,
      onSelect: onCreatePost,
    },
    {
      id: "reel",
      label: "Clip",
      icon: <ReelIcon />,
      onSelect: onCreateReel,
    },
    {
      id: "quick-trade",
      label: "Quick Trade",
      icon: <QuickTradeIcon />,
      onSelect: onCreateQuickTrade,
    },
  ]

  const handleItemAction = useCallback(
    (item: CreateMenuEntry) => {
      if (item.disabled || !item.onSelect) return
      close()
      item.onSelect()
    },
    [close]
  )

  useEffect(() => {
    setMounted(true)
  }, [])

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

  useEffect(() => {
    if (!open || !isMobile) return
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.body.style.overflow = prev
    }
  }, [open, isMobile])

  useEffect(() => {
    if (!open || isMobile) return
    function onPointerDown(e: MouseEvent | TouchEvent) {
      const root = rootRef.current
      if (!root) return
      if (!root.contains(e.target as Node)) close()
    }
    document.addEventListener("mousedown", onPointerDown)
    document.addEventListener("touchstart", onPointerDown)
    return () => {
      document.removeEventListener("mousedown", onPointerDown)
      document.removeEventListener("touchstart", onPointerDown)
    }
  }, [open, isMobile, close])

  const trigger =
    variant === "button" ? (
      <button
        type="button"
        onClick={() => setOpen((prev) => !prev)}
        aria-expanded={open}
        aria-haspopup="menu"
        className={
          className ??
          "inline-flex min-h-10 items-center justify-center rounded-md bg-blue-500 px-2.5 py-1.5 text-xs font-medium text-white transition hover:bg-blue-600 sm:min-h-0 sm:px-3 sm:py-2 sm:text-sm"
        }
      >
        + Create
      </button>
    ) : (
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-expanded={open}
        aria-haspopup="menu"
        className={
          className ?? "text-sm font-medium text-blue-300 hover:text-blue-200"
        }
      >
        Create →
      </button>
    )

  const sheet = open && isMobile && mounted
    ? createPortal(
        <div
          className="fixed inset-0 z-[10050] md:hidden"
          role="presentation"
          onClick={close}
        >
          <div
            className="absolute inset-0 bg-black/60 backdrop-blur-sm"
            aria-hidden
          />
          <div
            role="dialog"
            aria-modal="true"
            aria-label="Create content"
            className="absolute inset-x-0 bottom-0 rounded-t-2xl border border-white/10 bg-[#0b1f3a] shadow-2xl shadow-black/50"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex justify-center pt-3 pb-1">
              <div className="h-1 w-10 rounded-full bg-white/20" aria-hidden />
            </div>
            <div className="border-b border-white/10 px-4 pb-3">
              <h2 className="text-base font-semibold text-white">Create</h2>
              <p className="mt-0.5 text-xs text-gray-400">
                Share content with your followers
              </p>
            </div>
            <MenuOptionsList items={menuItems} onItemAction={handleItemAction} />
            <div className="border-t border-white/10 p-3">
              <button
                type="button"
                onClick={close}
                className="w-full rounded-lg border border-white/10 bg-white/5 px-4 py-2.5 text-sm font-medium text-gray-200 transition hover:bg-white/10"
              >
                Cancel
              </button>
            </div>
            <div className="h-[max(0.75rem,env(safe-area-inset-bottom))]" />
          </div>
        </div>,
        document.body
      )
    : null

  return (
    <div
      ref={rootRef}
      className={
        variant === "button" ? "relative shrink-0 sm:flex-none" : "inline-flex"
      }
    >
      {trigger}

      {open && !isMobile ? (
        <div
          role="menu"
          aria-label="Create content"
          className="absolute right-0 top-full z-50 mt-2 w-56 overflow-hidden rounded-xl border border-white/10 bg-[#0b1f3a] shadow-xl shadow-black/40"
        >
          <div className="border-b border-white/10 px-3 py-2">
            <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">
              Create
            </p>
          </div>
          <MenuOptionsList items={menuItems} onItemAction={handleItemAction} />
        </div>
      ) : null}

      {sheet}
    </div>
  )
}
