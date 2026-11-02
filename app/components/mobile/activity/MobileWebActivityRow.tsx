"use client"

import type { ReactNode } from "react"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"

type MobileWebActivityRowProps = {
  title: string
  subtitle?: string | null
  timestamp: string
  unread: boolean
  avatarUrl?: string | null
  onNavigate: () => void
  onDismiss: () => void
  dismissing?: boolean
  expandedContent?: ReactNode
}

export default function MobileWebActivityRow({
  title,
  subtitle,
  timestamp,
  unread,
  avatarUrl,
  onNavigate,
  onDismiss,
  dismissing = false,
  expandedContent,
}: MobileWebActivityRowProps) {
  return (
    <div
      className={`flex items-start gap-3 px-3 py-2.5 ${
        unread ? "bg-[color:color-mix(in_srgb,var(--tt-text)_6%,transparent)]" : ""
      }`}
    >
      <button
        type="button"
        onClick={onNavigate}
        className="flex min-w-0 flex-1 items-start gap-3 text-left"
      >
        <div className="relative shrink-0">
          {avatarUrl ? (
            <ProfileAvatarImg
              src={avatarUrl}
              className="h-10 w-10 ring-1 ring-[color:color-mix(in_srgb,var(--tt-text)_12%,transparent)]"
            />
          ) : (
            <div
              className="flex h-10 w-10 items-center justify-center rounded-full bg-[color:var(--tt-surface-nested,#1a222c)] text-[13px] font-semibold text-[color:var(--tt-text-muted,#c0cad6)]"
              aria-hidden
            >
              TT
            </div>
          )}
        </div>
        <div className="min-w-0 flex-1">
          <p
            className={`text-[15px] leading-snug text-[color:var(--tt-text,#f0f3f6)] ${
              unread ? "font-semibold" : "font-normal"
            }`}
          >
            {title}
          </p>
          {subtitle ? (
            <p className="mt-0.5 line-clamp-2 text-[12px] leading-snug text-[color:var(--tt-text-muted,#c0cad6)]">
              {subtitle}
            </p>
          ) : null}
          {expandedContent}
        </div>
        <div className="flex shrink-0 flex-col items-end gap-1 pt-0.5">
          <span className="text-[11px] tabular-nums text-[color:var(--tt-text-tertiary,#a8b3c2)]">
            {timestamp}
          </span>
          {unread ? (
            <span
              className="h-2 w-2 rounded-full bg-[color:var(--tt-accent,#4ec4e0)]"
              aria-hidden
            />
          ) : null}
        </div>
      </button>
      <button
        type="button"
        disabled={dismissing}
        onClick={(event) => {
          event.stopPropagation()
          onDismiss()
        }}
        className="mt-1 shrink-0 rounded-md p-1.5 text-[color:var(--tt-text-tertiary,#a8b3c2)] disabled:opacity-40"
        aria-label="Dismiss notification"
      >
        ✕
      </button>
    </div>
  )
}
