"use client"

import type { ReactNode } from "react"
import { cn } from "@/app/components/ui/cn"

/** Shared native header action hit target (~36px). */
export const NATIVE_IOS_PAGE_HEADER_ACTION_CLASS =
  "inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-white/10 text-white transition active:bg-white/20"

export type NativeIosPageHeaderProps = {
  /** Small left title when `leftContent` is not provided. */
  title?: string
  /** Custom left slot (e.g. account picker). Takes precedence over `title`. */
  leftContent?: ReactNode
  /** 0–3 contextual actions on the right. */
  rightActions?: ReactNode
  /** Sticky under the safe area (default true). */
  sticky?: boolean
  className?: string
}

/**
 * Standard native iOS page header chrome.
 * Height ~56px (excluding safe area). Presentation only.
 */
export default function NativeIosPageHeader({
  title,
  leftContent,
  rightActions,
  sticky = true,
  className,
}: NativeIosPageHeaderProps) {
  return (
    <header
      data-tt-native-page-header
      className={cn(
        "z-40 flex h-14 items-center gap-2 border-b border-white/10 bg-[var(--tt-surface,#1e3a8a)] px-3",
        sticky && "sticky",
        className
      )}
    >
      <div className="flex min-w-0 flex-1 items-center">
        {leftContent != null ? (
          leftContent
        ) : (
          <h1 className="min-w-0 truncate text-[17px] font-semibold tracking-tight text-white">
            {title ?? ""}
          </h1>
        )}
      </div>
      {rightActions ? (
        <div className="flex shrink-0 items-center gap-1.5">{rightActions}</div>
      ) : null}
    </header>
  )
}
